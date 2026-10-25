// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where in the source a record was made.
///
/// Every part may be unknown; a layout writes `?` for the ones that are, which
/// is what a call site without debug information looks like.
pub(all) struct Caller {
  module_path : String?
  func : String?
  file : String?
  line : Int32?
} derive(Eq, Debug)

///|
pub extend Caller with Debug::{to_repr}

///|
pub extend Caller with Eq::{equal, not_equal}

///|
pub fn Caller::new() -> Caller {
  { module_path: None, func: None, file: None, line: None, }
}

///|
/// The process and the deployment it is one instance of.
///
/// This is the only place where the library can learn who is writing: it is
/// passed in, never probed, so a test writes the identity it wants to check.
/// `offset` answers the seconds east of UTC at an instant, which is how a
/// local timestamp is written without the library owning a time zone database.
pub(all) struct Identity {
  app : String
  env : String
  instance : String
  host : String
  pid : Int32
  start : Int64
  offset : (Int64) -> Int32
}

///|
/// An identity that names nobody: the deployment a library has not been told
/// about.
pub fn Identity::new() -> Identity {
  {
    app: "",
    env: "",
    instance: "",
    host: "",
    pid: 0,
    start: 0L,
    offset: fn(_) { 0 },
  }
}

///|
/// An identity with the parts a deployment knows.
pub fn Identity::of(
  app~ : String,
  env~ : String = "",
  instance~ : String = "",
  host~ : String = "",
  pid~ : Int32 = 0,
  start~ : Int64 = 0L,
  offset~ : (Int64) -> Int32 = fn(_) { 0 },
) -> Identity {
  { app, env, instance, host, pid, start, offset, }
}

///|
/// One log event, as every sink sees it.
///
/// There is no clock in here either: `time` is what was handed in, in
/// nanoseconds since the epoch, and 0 means nobody said.
pub(all) struct Record {
  mut level : Level
  target : String
  mut msg : String
  mut fields : Array[(String, Value)]
  tags : Array[String]
  mut caller : Caller
  mut thread : String?
  mut spans : String?
  mut time : Int64
  mut seq : Int64
}

///|
/// A record with everything but its level, target and message left empty.
pub fn Record::of(level : Level, target : String, msg : String) -> Record {
  {
    level,
    target,
    msg,
    fields: [],
    tags: [],
    caller: Caller::new(),
    thread: None,
    spans: None,
    time: 0L,
    seq: 0L,
  }
}

///|
/// A copy, with the arrays copied too, so an edit cannot be seen elsewhere.
pub fn Record::copy(self : Record) -> Record {
  {
    level: self.level,
    target: self.target,
    msg: self.msg,
    fields: self.fields.copy(),
    tags: self.tags.copy(),
    caller: self.caller,
    thread: self.thread,
    spans: self.spans,
    time: self.time,
    seq: self.seq,
  }
}

///|
/// The same record with `key` set: an earlier field of that name takes the new
/// value where it stands, and a new name is appended, so the order a reader
/// sees is scope, then logger, then the call.
pub fn Record::set(self : Record, key : String, value : Value) -> Record {
  let out = self.copy()
  for i, (k, _) in out.fields {
    if k == key {
      out.fields[i] = (key, value)
      return out
    }
  }
  out.fields.push((key, value))
  out
}

///|
/// The same record with every pair set in turn.
pub fn Record::sets(self : Record, pairs : Array[(String, Value)]) -> Record {
  let mut out = self
  for pair in pairs {
    out = out.set(pair.0, pair.1)
  }
  out
}

///|
/// The same record with `key` gone.
pub fn Record::unset(self : Record, key : String) -> Record {
  let out = self.copy()
  let kept : Array[(String, Value)] = []
  for pair in out.fields {
    if pair.0 != key {
      kept.push(pair)
    }
  }
  out.fields = kept
  out
}

///|
/// The same record with another message.
pub fn Record::say(self : Record, msg : String) -> Record {
  let out = self.copy()
  out.msg = msg
  out
}

///|
/// The same record at another level.
pub fn Record::at(self : Record, level : Level) -> Record {
  let out = self.copy()
  out.level = level
  out
}

///|
/// The same record at an instant, in nanoseconds since the epoch.
pub fn Record::stamped(self : Record, time : Int64) -> Record {
  let out = self.copy()
  out.time = time
  out
}

///|
/// The same record numbered `seq`.
pub fn Record::numbered(self : Record, seq : Int64) -> Record {
  let out = self.copy()
  out.seq = seq
  out
}

///|
/// The same record carrying a source file and line.
pub fn Record::located(
  self : Record,
  file : String,
  line~ : Int32 = 0,
) -> Record {
  let out = self.copy()
  out.caller = {
    module_path: self.caller.module_path,
    func: self.caller.func,
    file: Some(file),
    line: Some(line),
  }
  out
}

///|
/// The same record carrying a thread name.
pub fn Record::on(self : Record, thread : String) -> Record {
  let out = self.copy()
  out.thread = Some(thread)
  out
}

///|
/// The last field called `key`.
pub fn Record::field(self : Record, key : String) -> Value? {
  let mut found = None
  for pair in self.fields {
    if pair.0 == key {
      found = Some(pair.1)
    }
  }
  found
}

///|
/// Whether any field is called `key`.
pub fn Record::has(self : Record, key : String) -> Bool {
  self.field(key) is Some(_)
}

///|
/// The same record carrying one more tag.
pub fn Record::tag(self : Record, tag : String) -> Record {
  let out = self.copy()
  out.tags.push(tag)
  out
}

///|
/// Whether the record carries `tag`.
pub fn Record::tagged(self : Record, tag : String) -> Bool {
  for t in self.tags {
    if t == tag {
      return true
    }
  }
  false
}
