// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How severe a message is, ordered from most verbose to least.
///
/// Six levels, which is the union of what the libraries here already had: a
/// server's `Trace` through `Critical` and a consensus core's `Debug` through
/// `Fatal`. `Critical` and `Fatal` are the same level under two names, so the
/// one kept is `Fatal`; `Panic`, which etcd's logger also aborts on, is not a
/// level but a thing the caller does after logging at `Fatal`.
pub(all) enum Level {
  Trace
  Debug
  Info
  Warning
  Error
  Fatal
} derive(Eq, Compare, Debug)

///|
pub extend Level with Eq::{equal, not_equal}

///|
pub extend Level with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
pub extend Level with Debug::{to_repr}

///|
/// A level prints as its name, so a line carrying one reads as a line.
pub impl Show for Level with fn output(self, logger) {
  logger.write_string(self.name())
}

///|
pub extend Level with Show::{output, to_string}

///|
/// The level's rank, low to high. A message is written when its level is at
/// least the logger's, which is the arrangement every logging library uses.
pub fn Level::rank(self : Level) -> Int {
  match self {
    Trace => 0
    Debug => 1
    Info => 2
    Warning => 3
    Error => 4
    Fatal => 5
  }
}

///|
/// The level's name as it appears in a line, upper case.
pub fn Level::name(self : Level) -> String {
  match self {
    Trace => "TRACE"
    Debug => "DEBUG"
    Info => "INFO"
    Warning => "WARNING"
    Error => "ERROR"
    Fatal => "FATAL"
  }
}

///|
/// A level by name, however it was capitalised.
///
/// It answers `None` rather than falling back to a level of its own choosing: a
/// configuration file with a typo in it should say so, not run at a verbosity
/// nobody asked for. The names other libraries use for the same level are
/// accepted — `warn`, `critical`, `fatal`, `err` — so a configuration written
/// for one of them keeps working.
pub fn Level::parse(name : StringView) -> Level? {
  match name.to_lower() {
    "trace" => Some(Trace)
    "debug" => Some(Debug)
    "info" => Some(Info)
    "warn" | "warning" => Some(Warning)
    "err" | "error" => Some(Error)
    "fatal" | "critical" => Some(Fatal)
    _ => None
  }
}

///|
/// One message on its way out.
///
/// There is no timestamp. A library has no clock — reading one is a side effect
/// and a logger that stamps the time cannot be tested for what it wrote — so the
/// instant, when it is wanted, comes from the sink that was handed a clock. The
/// same reasoning as `mooncred`'s verification taking its `now`.
pub(all) struct Record {
  level : Level
  message : String
  /// Structured fields, in the order they were given. `Json` is a builtin, so
  /// carrying values rather than pre-formatted text costs no dependency.
  fields : Array[(String, Json)]
}

///|
/// Where records go.
///
/// A trait rather than a function so a sink can hold state — a buffer, a file, a
/// clock, a counter — and so an embedder can route lines into its own logging
/// without this library knowing anything about it.
pub(open) trait Sink {
  fn write(Self, Record) -> Unit
}

///|
/// A logger: a level to filter by and somewhere to write.
///
/// The filter is a `Level?` rather than a `Level` because "write nothing at all"
/// is not a level — a message is never of severity "off" — and a silent logger
/// has to be able to say so to [`enabled`], so a caller skips building a message
/// it would only throw away.
pub struct Logger {
  filter : Level?
  sink : &Sink
}

///|
/// The level a logger runs at when nothing says otherwise.
///
/// `Info` is what every library here defaults to, and what Python's `logging`,
/// Go's `slog` and go-zero all settle on: a deployment wants to hear about what
/// happened, not about every step taken to get there.
pub let level : Level = Info

///|
/// A logger writing to `sink` at `level`.
pub fn Logger::new(sink : &Sink, level? : Level = level) -> Logger {
  { filter: Some(level), sink, }
}

///|
/// A logger that writes nothing, for an embedder that does its own reporting and
/// for a test that would rather not have output.
///
/// It is not a logger at level `Fatal`: [`enabled`] answers false at every level,
/// so a caller that builds an expensive message only when it will be used builds
/// none at all.
pub fn Logger::silent() -> Logger {
  { filter: None, sink: Discard::{ }, }
}

///|
/// The level this logger writes at, or `None` if it writes nothing.
pub fn Logger::level(self : Logger) -> Level? {
  self.filter
}

///|
/// The same logger at another level.
pub fn Logger::at(self : Logger, level : Level) -> Logger {
  { filter: Some(level), sink: self.sink, }
}

///|
/// Whether a message at `level` would be written.
///
/// Worth asking before assembling a message that costs something: a logger
/// cannot skip work its caller has already done.
pub fn Logger::enabled(self : Logger, level : Level) -> Bool {
  match self.filter {
    Some(filter) => level.rank() >= filter.rank()
    None => false
  }
}

///|
/// Write a message, with fields if there are any.
pub fn Logger::log(
  self : Logger,
  level : Level,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  if self.enabled(level) {
    self.sink.write({ level, message, fields, })
  }
}

///|
/// Write at `Trace`.
pub fn Logger::trace(
  self : Logger,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  self.log(Trace, message, fields~)
}

///|
/// Write at `Debug`.
pub fn Logger::debug(
  self : Logger,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  self.log(Debug, message, fields~)
}

///|
/// Write at `Info`.
pub fn Logger::info(
  self : Logger,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  self.log(Info, message, fields~)
}

///|
/// Write at `Warning`.
pub fn Logger::warn(
  self : Logger,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  self.log(Warning, message, fields~)
}

///|
/// Write at `Error`.
pub fn Logger::error(
  self : Logger,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  self.log(Error, message, fields~)
}

///|
/// Write at `Fatal`. It does not abort — what to do after the last message is
/// the caller's to decide, and a library that ends the process takes that
/// decision away.
pub fn Logger::fatal(
  self : Logger,
  message : String,
  fields? : Array[(String, Json)] = [],
) -> Unit {
  self.log(Fatal, message, fields~)
}

///|
/// A sink that drops everything.
pub(all) struct Discard {}

///|
pub impl Sink for Discard with fn write(_self, _record) {

}

///|
pub extend Discard with Sink::{write}

///|
/// A sink that hands each line to a function.
///
/// This is the seam: `Lines::new(line => println(line))` prints, and
/// `Lines::new(line => held.push(line))` is how a test reads what was written.
pub struct Lines {
  write : (String) -> Unit
  format : (Record) -> String
}

///|
/// A sink writing one line per record through `write`.
///
/// `format` turns a record into that line; [`line`] is the default and writes
/// `LEVEL message key=value`, which is what a person reads. For something a
/// machine reads, [`json_line`] writes one JSON object instead.
pub fn Lines::new(
  write : (String) -> Unit,
  format? : (Record) -> String = line,
) -> Lines {
  { write, format, }
}

///|
pub impl Sink for Lines with fn write(self, record) {
  (self.write)((self.format)(record))
}

///|
pub extend Lines with Sink::{write}

///|
/// A record as `LEVEL message key=value key=value`.
///
/// Values are written as their JSON, so a string keeps its quotes and a field
/// containing a space cannot be mistaken for two fields.
pub fn line(record : Record) -> String {
  let out = StringBuilder()
  out.write_string(record.level.name())
  out.write_char(' ')
  out.write_string(record.message)
  for field in record.fields {
    out.write_char(' ')
    out.write_string(field.0)
    out.write_char('=')
    out.write_string(field.1.stringify())
  }
  out.to_string()
}

///|
/// The key the level is written under.
///
/// `level` and `msg` are what go-zero, zap and Go's `slog` all name them, so a
/// line from here drops into a log pipeline already built for one of those.
pub let level_key : String = "level"

///|
/// The key the message is written under.
pub let message_key : String = "msg"

///|
/// One record as a single JSON object, for a reader that is a machine.
///
/// The level and the message come first, then the fields in the order they were
/// given. A field named `level` or `msg` replaces the one this writes rather than
/// appearing twice: an object with a key twice is a document readers disagree
/// about, and the caller naming it meant it.
pub fn json_line(record : Record) -> String {
  object(record)
}

///|
/// The same, with the two keys named.
///
/// A pipeline that expects `severity` and `message` rather than `level` and
/// `msg` is common enough — Google Cloud Logging is one — that renaming them is
/// a parameter rather than a reason to write your own formatter.
pub fn object(
  record : Record,
  level? : String = level_key,
  message? : String = message_key,
) -> String {
  let out : Map[String, Json] = Map([])
  out[level] = Json::string(record.level.name())
  out[message] = Json::string(record.message)
  for field in record.fields {
    out[field.0] = field.1
  }
  // The object is written in insertion order, so the level and the message stay
  // in front where a person skimming the stream can find them.
  Json::object(out).stringify()
}
