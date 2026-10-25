// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A target and the fields bound to it: what a module or a request holds and
/// writes through.
///
/// A logger is a value. It is passed in, it can be copied, and a library that
/// was handed none writes nothing — there is no default one to inherit.
pub struct Logger {
  hub : Hub
  target : String
  fields : Array[(String, Value)]
}

///|
/// A logger writing to `hub` under `target`.
pub fn Logger::new(hub : Hub, target : String) -> Logger {
  { hub, target, fields: [], }
}

///|
/// The target it writes under.
pub fn Logger::target(self : Logger) -> String {
  self.target
}

///|
/// The same logger with `key` bound, so every line it writes carries it.
pub fn Logger::bound(self : Logger, key : String, value : Value) -> Logger {
  let fields = self.fields.copy()
  let mut replaced = false
  for i, (name, _) in fields {
    if name == key {
      fields[i] = (key, value)
      replaced = true
    }
  }
  if !replaced {
    fields.push((key, value))
  }
  { hub: self.hub, target: self.target, fields, }
}

///|
/// The same logger under another target, which is what a submodule is.
pub fn Logger::under(self : Logger, target : String) -> Logger {
  { hub: self.hub, target, fields: self.fields, }
}

///|
/// Whether a message at `level` would be written.
///
/// Worth asking before assembling a message that costs something: a logger
/// cannot skip work its caller has already done.
pub fn Logger::enabled(self : Logger, level : Level) -> Bool {
  self.hub.enabled(level)
}

///|
/// Writes a message, with fields if there are any.
pub fn Logger::log(
  self : Logger,
  level : Level,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  if !self.enabled(level) {
    return
  }
  let all = self.fields.copy()
  for pair in fields {
    all.push(pair)
  }
  self.hub.write(level, self.target, msg, fields=all)
}

///|
/// Writes at `trace`.
pub fn Logger::trace(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  self.log(trace, msg, fields~)
}

///|
/// Writes at `debug`.
pub fn Logger::debug(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  self.log(debug, msg, fields~)
}

///|
/// Writes at `info`.
pub fn Logger::info(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  self.log(info, msg, fields~)
}

///|
/// Writes at `warn`.
pub fn Logger::warn(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  self.log(warn, msg, fields~)
}

///|
/// Writes at `error`.
pub fn Logger::error(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  self.log(error, msg, fields~)
}

///|
/// Writes at `fatal`. It does not abort: what to do after the last line is the
/// caller's to decide, and a library that ends the process takes that decision
/// away.
pub fn Logger::fatal(
  self : Logger,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  self.log(fatal, msg, fields~)
}
