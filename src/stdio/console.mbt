// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink that writes each entry as one line on the console.
///
/// `Auto` sends a record to standard error when its level reaches `from` and to
/// standard output otherwise, which is what a pipeline wants: the log stream
/// can be redirected while failures still reach the terminal.
///
/// Whether the line carries colour is settled once, when the console is built,
/// and the slot has to be told the same answer: `Console::slot` does both.
pub struct Console {
  stream : @moonlog.Stream
  colour : Bool
  from : @moonlog.Level
}

///|
/// A console on `stream`.
///
/// `colour` decides whether the slot writes escapes: leave it out and the
/// console asks the environment and the terminal (see `decide`). `from` is the
/// level at which `Auto` starts using standard error; every level from `error`
/// up unless it is given.
pub fn Console::new(
  stream? : @moonlog.Stream,
  colour? : Bool,
  from? : @moonlog.Level,
) -> Console {
  let stream = match stream {
    Some(given) => given
    None => @moonlog.Stream::Auto
  }
  let from = match from {
    Some(given) => given
    None => @moonlog.error
  }
  let colour = match colour {
    Some(given) => given
    None => decide(terminal(stream), no_color(), force_color())
  }
  { stream, colour, from, }
}

///|
/// The stream this console was built for.
pub fn Console::stream(self : Console) -> @moonlog.Stream {
  self.stream
}

///|
/// Whether this console's lines carry escapes.
pub fn Console::coloured(self : Console) -> Bool {
  self.colour
}

///|
/// The level at which `Auto` turns to standard error.
pub fn Console::from(self : Console) -> @moonlog.Level {
  self.from
}

///|
/// The stream a record at `level` is written to.
pub fn Console::target(
  self : Console,
  level : @moonlog.Level,
) -> @moonlog.Stream {
  match self.stream {
    @moonlog.Stream::Auto =>
      if level.at_least(self.from) {
        @moonlog.Stream::Stderr
      } else {
        @moonlog.Stream::Stdout
      }
    fixed => fixed
  }
}

///|
/// A slot around this console, already coloured the way the console decided.
pub fn Console::slot(
  self : Console,
  name~ : String = "console",
) -> @moonlog.Slot {
  @moonlog.Slot::new(self, name~).kind("stdio").coloured(self.colour)
}

///|
/// Writes one line to `stream`.
///
/// The line is encoded once, here: a console with a file descriptor writes
/// those bytes, a host that prints takes the string. Neither target re-encodes
/// what the layout made.
fn put(stream : @moonlog.Stream, line : String) -> Result[Unit, String] {
  put_line(stream, line, @utf8.encode(line + "\n"))
}

///|
pub impl @moonlog.Sink for Console with fn write(self, entry) {
  put(self.target(entry.record.level), entry.line)
}

///|
pub extend Console with @moonlog.Sink::{write}
