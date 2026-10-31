// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One entry waiting to be shipped: what it says, when it happened, and the
/// fields that go with it.
struct Pending {
  level : @moonlog.Level
  at : Int64
  line : String
  meta : Array[(String, String)]
}

///|
/// A sink that ships entries to Loki.
///
/// `write` only queues: a log call must not wait for a network. `push` does
/// the sending, from an async context the application already runs, so the
/// retry that a busy Loki asks for lives in the caller's loop — and the slot's
/// own queue, retries and health machine still govern how the sink is treated
/// when a push keeps failing.
///
/// Each level gets a stream of its own, so a query can select on it without
/// parsing a line, and the entry's fields travel as structured metadata.
pub struct Loki {
  url : String
  labels : Array[(String, String)]
  tenant : String?
  auth : (String, String)?
  limits : Limits
  clock : () -> Int64
  held : Array[Pending]
  mut sent : Int64
  mut rejected : Int64
  mut dropped : Int64
  mut failures : Int64
}

///|
/// A sink pushing to `url`, which is the Loki base address: `/loki/api/v1/push`
/// is appended unless the address already ends with it.
///
/// `labels` are the stream's own, such as the job and the host; the level is
/// added per stream. `auth` is a user and password for basic authentication,
/// and `tenant` is sent as `X-Scope-OrgID` for a multi-tenant Loki.
pub fn Loki::new(
  url~ : String,
  labels~ : Array[(String, String)] = [],
  tenant? : String,
  auth? : (String, String),
  limits~ : Limits = Limits::new(),
  clock~ : () -> Int64 = fn() { @env.now().reinterpret_as_int64() * 1_000_000L },
) -> Loki {
  let address = if url.has_suffix("/loki/api/v1/push") {
    url
  } else {
    let trimmed = if url.has_suffix("/") {
      url[:url.length() - 1].to_owned()
    } else {
      url
    }
    trimmed + "/loki/api/v1/push"
  }
  {
    url: address,
    labels,
    tenant,
    auth,
    limits,
    clock,
    held: [],
    sent: 0L,
    rejected: 0L,
    dropped: 0L,
    failures: 0L,
  }
}

///|
/// The address entries are pushed to.
pub fn Loki::url(self : Loki) -> String {
  self.url
}

///|
/// How many entries are waiting.
pub fn Loki::pending(self : Loki) -> Int32 {
  self.held.length()
}

///|
/// How many entries Loki has taken.
pub fn Loki::sent(self : Loki) -> Int64 {
  self.sent
}

///|
/// How many Loki refused for good.
pub fn Loki::rejected(self : Loki) -> Int64 {
  self.rejected
}

///|
/// How many were dropped because the queue was full.
pub fn Loki::dropped(self : Loki) -> Int64 {
  self.dropped
}

///|
/// How many pushes came back with something to retry.
pub fn Loki::failures(self : Loki) -> Int64 {
  self.failures
}

///|
/// A slot around this sink.
pub fn Loki::slot(self : Loki, name~ : String = "loki") -> @moonlog.Slot {
  @moonlog.Slot::new(self, name~).kind("loki")
}

///|
/// Queues one entry. The oldest entry goes when the queue is full.
fn Loki::keep(self : Loki, item : Pending) -> Unit {
  if self.held.length() >= self.limits.capacity {
    let kept : Array[Pending] = []
    for i in 1..<self.held.length() {
      kept.push(self.held[i])
    }
    self.held.clear()
    for item in kept {
      self.held.push(item)
    }
    self.dropped = self.dropped + 1L
  }
  self.held.push(item)
}

///|
pub impl @moonlog.Sink for Loki with fn write(self, entry) {
  let meta : Array[(String, String)] = []
  for pair in entry.record.fields {
    meta.push((pair.0, pair.1.to_text()))
  }
  self.keep({
    level: entry.record.level,
    at: if entry.record.time == 0L {
      (self.clock)()
    } else {
      entry.record.time
    },
    line: entry.line,
    meta,
  })
  Ok(())
}

///|
pub extend Loki with @moonlog.Sink::{write}

///|
/// Takes up to `batch` entries off the queue.
fn Loki::take(self : Loki) -> Array[Pending] {
  let count = if self.held.length() > self.limits.batch {
    self.limits.batch
  } else {
    self.held.length()
  }
  let taken : Array[Pending] = []
  let rest : Array[Pending] = []
  for i in 0..<self.held.length() {
    if i < count {
      taken.push(self.held[i])
    } else {
      rest.push(self.held[i])
    }
  }
  self.held.clear()
  for item in rest {
    self.held.push(item)
  }
  taken
}

///|
/// Puts a batch back at the front of the queue, keeping what arrived since.
fn Loki::restore(self : Loki, items : Array[Pending]) -> Unit {
  let held : Array[Pending] = []
  for item in items {
    held.push(item)
  }
  for item in self.held {
    held.push(item)
  }
  self.held.clear()
  for item in held {
    self.held.push(item)
  }
  while self.held.length() > self.limits.capacity {
    ignore(self.take_oldest())
  }
}

///|
/// Removes the oldest entry, counting it as dropped.
fn Loki::take_oldest(self : Loki) -> Pending? {
  if self.held.length() == 0 {
    return None
  }
  let oldest = self.held[0]
  let kept : Array[Pending] = []
  for i in 1..<self.held.length() {
    kept.push(self.held[i])
  }
  self.held.clear()
  for item in kept {
    self.held.push(item)
  }
  self.dropped = self.dropped + 1L
  Some(oldest)
}

///|
/// The push body the pending entries would make, without taking them.
///
/// What a check before a deployment prints, and what a test reads instead of
/// standing up a server.
pub fn Loki::body(self : Loki) -> String {
  let count = if self.held.length() > self.limits.batch {
    self.limits.batch
  } else {
    self.held.length()
  }
  let batch : Array[Pending] = []
  for i in 0..<count {
    batch.push(self.held[i])
  }
  self.encode(batch)
}

///|
/// Pushes one batch, and answers what became of it.
///
/// Call it from a loop the application already runs; `retry` in the answer is
/// that loop's cue to wait and come back, and everything it did not send stays
/// queued, in order.
pub async fn Loki::push(self : Loki) -> Report {
  if self.held.length() == 0 {
    return Report::idle()
  }
  let batch = self.take()
  let body = self.encode(batch)
  let headers : Array[(String, String)] = [("content-type", "application/json")]
  match self.tenant {
    Some(tenant) => headers.push(("x-scope-orgid", tenant))
    None => ()
  }
  match self.auth {
    Some((user, password)) =>
      headers.push(("authorization", "Basic " + basic(user, password)))
    None => ()
  }
  let answer = @moonfetch.post(
    self.url,
    body=@moonfetch.Body::Text(body),
    headers~,
    timeout=self.limits.timeout,
  )
  match Verdict::of(answer.status) {
    Accepted => {
      self.sent = self.sent + batch.length().to_int64()
      { sent: batch.length(), rejected: 0, retry: None, }
    }
    Refused => {
      // Loki will not take these, ever: say how many, and move on.
      self.rejected = self.rejected + batch.length().to_int64()
      { sent: 0, rejected: batch.length(), retry: None, }
    }
    Retry => {
      self.failures = self.failures + 1L
      self.restore(batch)
      { sent: 0, rejected: 0, retry: Some(reason_of(answer.status)), }
    }
  }
}

///|
/// `user:password`, base64, for basic authentication.
fn basic(user : String, password : String) -> String {
  @base64.encode(@utf8.encode(user + ":" + password))
}

///|
/// The push body: one stream per level, each with its own labels.
pub fn Loki::encode(self : Loki, batch : Array[Pending]) -> String {
  let order : Array[String] = []
  let groups : Map[String, Array[Pending]] = Map([])
  for item in batch {
    let name = item.level.name()
    match groups.get(name) {
      Some(group) => group.push(item)
      None => {
        groups[name] = [item]
        order.push(name)
      }
    }
  }
  let out = StringBuilder()
  out.write_string("{\"streams\":[")
  let mut first = true
  for name in order {
    if !first {
      out.write_string(",")
    }
    first = false
    out.write_string("{\"stream\":{")
    out.write_string("\"level\":")
    out.write_string(quoted(name))
    for label in self.labels {
      out.write_string(",")
      out.write_string(quoted(label.0))
      out.write_string(":")
      out.write_string(quoted(label.1))
    }
    out.write_string("},\"values\":[")
    let group = match groups.get(name) {
      Some(group) => group
      None => []
    }
    let mut first_value = true
    for item in group {
      if !first_value {
        out.write_string(",")
      }
      first_value = false
      out.write_string("[\"")
      out.write_string(item.at.to_string())
      out.write_string("\",")
      out.write_string(quoted(item.line))
      if item.meta.length() > 0 {
        out.write_string(",{")
        let mut first_meta = true
        for pair in item.meta {
          if !first_meta {
            out.write_string(",")
          }
          first_meta = false
          out.write_string(quoted(pair.0))
          out.write_string(":")
          out.write_string(quoted(pair.1))
        }
        out.write_string("}")
      }
      out.write_string("]")
    }
    out.write_string("]}")
  }
  out.write_string("]}")
  out.to_string()
}

///|
/// A JSON string literal, escaped by the same code that writes a field.
fn quoted(text : String) -> String {
  @moonlog.Value::of_str(text).encode()
}
