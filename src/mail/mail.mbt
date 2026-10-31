// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink that mails the records a deployment cannot afford to lose.
///
/// It is the mail handler a service already knows: a level of its own, a
/// window in which a burst becomes one mail, and a ceiling on how many records
/// one mail carries. `write` only queues — a log call never waits for SMTP —
/// and `send` does the talking, from the application's own async loop. When
/// the server is down the mail stays queued, and the slot's retries, health
/// machine and alarm take over from there.
pub struct Mail {
  host : String
  port : Int32
  security : Security
  tls : @tls.Client?
  auth : (String, String)?
  from : String
  to : Array[String]
  subject : String
  level : @moonlog.Level
  window : Int64
  at_most : Int32
  capacity : Int32
  clock : () -> Int64
  held : Array[Held]
  mut sent : Int64
  mut dropped : Int64
  mut failures : Int64
}

///|
/// A sink mailing through `host`.
///
/// `from` is the envelope sender and `to` the recipients, both as addresses.
/// `subject` is a template: `{count}` (a number), `{records}` (the number and
/// the noun that goes with it), `{level}` and `{target}` are filled in from
/// the batch. `level` is the floor this sink is interested in — it mails
/// what a slot would already have let through, but a sink built beside a
/// console slot gets the whole stream, and this is what keeps a queued warning
/// out of the on-call inbox.
///
/// `security` decides how the connection is protected; `StartTls` and `Tls`
/// need `tls`, a client with its own trust store, because which roots to trust
/// is the application's decision and not this sink's.
pub fn Mail::new(
  host~ : String,
  from~ : String,
  to~ : Array[String],
  port? : Int32,
  security~ : Security = Security::Clear,
  tls? : @tls.Client,
  auth? : (String, String),
  subject~ : String = "{level}: {records} from {target}",
  level~ : @moonlog.Level = @moonlog.error,
  window~ : Int64 = window_default,
  at_most~ : Int32 = at_most_default,
  capacity~ : Int32 = 512,
  clock~ : () -> Int64 = fn() { @env.now().reinterpret_as_int64() * 1_000_000L },
) -> Mail {
  let port = match port {
    Some(port) => port
    None => security.port()
  }
  {
    host,
    port,
    security,
    tls,
    auth,
    from,
    to,
    subject,
    level,
    window,
    at_most,
    capacity,
    clock,
    held: [],
    sent: 0L,
    dropped: 0L,
    failures: 0L,
  }
}

///|
/// The floor this sink mails at.
pub fn Mail::level(self : Mail) -> @moonlog.Level {
  self.level
}

///|
/// How long a batch is gathered.
pub fn Mail::window(self : Mail) -> Int64 {
  self.window
}

///|
/// How many records one mail carries.
pub fn Mail::at_most(self : Mail) -> Int32 {
  self.at_most
}

///|
/// How many records are waiting.
pub fn Mail::pending(self : Mail) -> Int32 {
  self.held.length()
}

///|
/// How many records have been mailed.
pub fn Mail::sent(self : Mail) -> Int64 {
  self.sent
}

///|
/// How many records were dropped because the queue was full.
pub fn Mail::dropped(self : Mail) -> Int64 {
  self.dropped
}

///|
/// How many sends failed and left their records queued.
pub fn Mail::failures(self : Mail) -> Int64 {
  self.failures
}

///|
/// A slot around this sink.
pub fn Mail::slot(self : Mail, name~ : String = "mail") -> @moonlog.Slot {
  @moonlog.Slot::new(self, name~).kind("mail").at(self.level)
}

///|
/// Whether a batch is ready at `now`: the oldest record has waited out the
/// window, or there are enough of them to fill a mail.
pub fn Mail::due(self : Mail, now : Int64) -> Bool {
  if self.held.length() == 0 {
    return false
  }
  if self.held.length() >= self.at_most {
    return true
  }
  now - self.held[0].at >= self.window
}

///|
pub impl @moonlog.Sink for Mail with fn write(self, entry) {
  if !entry.record.level.at_least(self.level) {
    return Ok(())
  }
  if self.held.length() >= self.capacity {
    // A mail queue that unrolls into an outage is not worth much: the oldest
    // goes, and the count says so.
    let kept : Array[Held] = []
    for i in 1..<self.held.length() {
      kept.push(self.held[i])
    }
    self.held.clear()
    for item in kept {
      self.held.push(item)
    }
    self.dropped = self.dropped + 1L
  }
  self.held.push({
    at: entry.record.time,
    level: entry.record.level,
    target: entry.record.target,
    line: entry.line,
    fields: entry.record.fields,
  })
  Ok(())
}

///|
pub extend Mail with @moonlog.Sink::{write}

///|
/// Takes up to `at_most` records, oldest first.
fn Mail::take(self : Mail) -> Array[Held] {
  let count = if self.held.length() > self.at_most {
    self.at_most
  } else {
    self.held.length()
  }
  let taken : Array[Held] = []
  let rest : Array[Held] = []
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
/// Puts a batch back at the front, keeping what arrived since.
fn Mail::restore(self : Mail, batch : Array[Held]) -> Unit {
  let held : Array[Held] = []
  for item in batch {
    held.push(item)
  }
  for item in self.held {
    held.push(item)
  }
  self.held.clear()
  for item in held {
    if self.held.length() < self.capacity {
      self.held.push(item)
    } else {
      self.dropped = self.dropped + 1L
    }
  }
}

///|
/// The subject a batch is mailed under.
pub fn Mail::subject_for(self : Mail, batch : Array[Held]) -> String {
  let highest = highest_of(batch)
  let target = if batch.length() > 0 { batch[0].target } else { "" }
  let out = StringBuilder()
  let chars = self.subject.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' {
      let mut end = i + 1
      while end < chars.length() && chars[end] != '}' {
        end = end + 1
      }
      if end < chars.length() {
        let name = self.subject[i + 1:end].to_owned()
        match name {
          "count" => out.write_string(batch.length().to_string())
          "records" => {
            let noun = if batch.length() == 1 { " record" } else { " records" }
            out.write_string(batch.length().to_string() + noun)
          }
          "level" => out.write_string(highest.name().to_upper())
          "target" => out.write_string(target)
          _ => out.write_string(self.subject[i:end + 1].to_owned())
        }
        i = end + 1
        continue
      }
    }
    out.write_char(chars[i])
    i = i + 1
  }
  out.to_string()
}

///|
/// The highest level in a batch, which is what the subject leads with.
fn highest_of(batch : Array[Held]) -> @moonlog.Level {
  let mut highest = @moonlog.trace
  for item in batch {
    if item.level.value > highest.value {
      highest = item.level
    }
  }
  highest
}

///|
/// The plain text body: one line per record, as the slots wrote them.
pub fn Mail::text_for(_self : Mail, batch : Array[Held]) -> String {
  let out = StringBuilder()
  for item in batch {
    out.write_string(item.line)
    out.write_string("\n")
  }
  out.to_string()
}

///|
/// The HTML body: the same lines in a table, with the fields that came with
/// them, so an inbox shows the same thing a console does.
pub fn Mail::html_for(_self : Mail, batch : Array[Held]) -> String {
  let out = StringBuilder()
  out.write_string(
    "<table cellspacing=\"0\" cellpadding=\"4\"><thead><tr>" +
    "<th align=\"left\">time</th><th align=\"left\">level</th>" +
    "<th align=\"left\">target</th><th align=\"left\">message</th>" +
    "<th align=\"left\">fields</th></tr></thead><tbody>",
  )
  for item in batch {
    out.write_string("<tr><td>")
    out.write_string(escaped(stamp_of(item.at)))
    out.write_string("</td><td>")
    out.write_string(escaped(item.level.name().to_upper()))
    out.write_string("</td><td>")
    out.write_string(escaped(item.target))
    out.write_string("</td><td>")
    out.write_string(escaped(record_message(item.line, item.target)))
    out.write_string("</td><td>")
    let mut first = true
    for pair in item.fields {
      if !first {
        out.write_string("<br/>")
      }
      first = false
      out.write_string(escaped(pair.0))
      out.write_string("=")
      out.write_string(escaped(pair.1.to_text()))
    }
    out.write_string("</td></tr>")
  }
  out.write_string("</tbody></table>")
  out.to_string()
}

///|
/// The message part of a formatted line: what follows `target: `, so the table
/// does not repeat the target it put in its own column.
fn record_message(line : String, target : String) -> String {
  let needle = target + ": "
  match line.find(needle) {
    Some(at) => line[at + needle.length():].to_owned()
    None => line
  }
}

///|
/// `2023-11-14 22:13:20.000`, in UTC, which is what a mail header can promise.
fn stamp_of(at : Int64) -> String {
  let out = StringBuilder()
  @moonlog.Clock::Utc.write(out, at, 0)
  out.to_string()
}

///|
/// A string with the five characters HTML reserves replaced.
fn escaped(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    match c {
      '&' => out.write_string("&amp;")
      '<' => out.write_string("&lt;")
      '>' => out.write_string("&gt;")
      '"' => out.write_string("&quot;")
      '\'' => out.write_string("&#39;")
      _ => out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// The mail a batch becomes, ready to encode.
pub fn Mail::letter(
  self : Mail,
  batch : Array[Held],
) -> @moonmail.Message raise @moonmail.Refused {
  let sender = @moonmail.Mailbox::new(self.from)
  let recipients : Array[@moonmail.Address] = []
  for address in self.to {
    recipients.push(@moonmail.Address::Mailbox(@moonmail.Mailbox::new(address)))
  }
  let at = if batch.length() > 0 { batch[0].at } else { (self.clock)() }
  @moonmail.Message::new(
    from=sender,
    to=recipients,
    subject=self.subject_for(batch),
    text=self.text_for(batch),
    html=self.html_for(batch),
    date=@moondate.Moment::of_epoch(
      at / 1_000_000_000L,
      nano=(at % 1_000_000_000L).to_int(),
    ),
  )
}

///|
/// The mail the pending records would become, without sending it.
///
/// What a check before a deployment prints, and what a test reads instead of
/// standing up a server.
pub fn Mail::draft(self : Mail) -> @moonmail.Message raise @moonmail.Refused {
  let count = if self.held.length() > self.at_most {
    self.at_most
  } else {
    self.held.length()
  }
  let batch : Array[Held] = []
  for i in 0..<count {
    batch.push(self.held[i])
  }
  self.letter(batch)
}

///|
/// Sends one batch, and answers how many records it carried.
///
/// Records that could not be sent stay queued, in order, for the next call;
/// the failure is the answer, so the caller's loop decides when to try again.
pub async fn Mail::send(self : Mail) -> Result[Int32, String] {
  if self.held.length() == 0 {
    return Ok(0)
  }
  let batch = self.take()
  let letter = self.letter(batch) catch {
    error => {
      self.failures = self.failures + 1L
      self.restore(batch)
      return Err("the mail would not build: " + @debug.to_string(error))
    }
  }
  let security = match self.security {
    Clear => @net.Security::Clear
    StartTls =>
      match self.tls {
        Some(client) => @net.Security::StartTls(client)
        None => {
          self.failures = self.failures + 1L
          self.restore(batch)
          return Err("STARTTLS needs a trust store: pass `tls` to Mail::new")
        }
      }
    Tls =>
      match self.tls {
        Some(client) => @net.Security::Tls(client)
        None => {
          self.failures = self.failures + 1L
          self.restore(batch)
          return Err("TLS needs a trust store: pass `tls` to Mail::new")
        }
      }
  }
  let now = (self.clock)()
  let smtp = @net.Smtp::connect(self.host, security, port=self.port, now~)
  match self.auth {
    Some((user, password)) => smtp.auth(@sasl.Plain::new(user, password))
    None => ()
  }
  let replies = smtp.send(self.from, self.to, letter.encode())
  smtp.quit()
  let mut refused = None
  for pair in replies {
    if !pair.1.is_ok() {
      refused = Some(pair.0 + ": " + pair.1.text())
    }
  }
  match refused {
    Some(why) => {
      self.failures = self.failures + 1L
      self.restore(batch)
      Err("the server refused the mail: " + why)
    }
    None => {
      self.sent = self.sent + batch.length().to_int64()
      Ok(batch.length())
    }
  }
}
