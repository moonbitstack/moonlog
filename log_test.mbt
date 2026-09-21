// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A logger writing into an array, which is how a test reads what was said.
fn capture(
  level? : @moonlog.Level = Info,
  format? : (@moonlog.Record) -> String = @moonlog.line,
) -> (@moonlog.Logger, Array[String]) {
  let held : Array[String] = []
  (
    @moonlog.Logger::new(
      @moonlog.Lines::new(line => held.push(line), format~),
      level~,
    ),
    held,
  )
}

///|
/// The levels are ordered, and a message is written when it is at least as
/// severe as the logger's — the arrangement every logging library uses.
test "a level below the logger's is not written" {
  let (log, held) = capture()
  log.trace("no")
  log.debug("no")
  log.info("yes")
  log.warn("yes")
  log.error("yes")
  log.fatal("yes")
  assert_eq(held.length(), 4)
  assert_eq(held[0], "INFO yes")
  assert_eq(held[3], "FATAL yes")
  // And `enabled` answers the same question before the message is built.
  assert_false(log.enabled(Trace))
  assert_false(log.enabled(Debug))
  assert_true(log.enabled(Info))
  assert_true(log.enabled(Fatal))
}

///|
/// The level is a knob at every point: on construction, and on a logger that
/// already exists.
test "the level is a knob" {
  let (log, held) = capture(level=Trace)
  log.trace("kept")
  assert_eq(held.length(), 1)
  let quiet = log.at(Error)
  quiet.warn("dropped")
  assert_eq(held.length(), 1)
  quiet.error("kept")
  assert_eq(held.length(), 2)
  // The original is unchanged: `at` answers a new logger rather than turning
  // the old one down under everyone holding it.
  log.trace("still kept")
  assert_eq(held.length(), 3)
  assert_eq(log.level(), Some(Trace))
  assert_eq(quiet.level(), Some(Error))
  // The preset is the one every library here defaulted to.
  assert_eq(@moonlog.level, Info)
  assert_eq(@moonlog.Logger::new(@moonlog.Discard::{ }).level(), Some(Info))
}

///|
/// Silence is not a level. A silent logger says no at every one, so a caller
/// that only builds an expensive message when it will be used builds none.
test "silence is not a level" {
  let quiet = @moonlog.Logger::silent()
  for level in [@moonlog.Level::Trace, Debug, Info, Warning, Error, Fatal] {
    assert_false(quiet.enabled(level))
  }
  assert_eq(quiet.level(), None)
  // And nothing reaches a sink, which is the other half of the promise: the
  // same logger with somewhere to write would have written six lines.
  let seen : Array[@moonlog.Record] = []
  @moonlog.Logger::silent().fatal("nobody hears this")
  assert_eq(seen.length(), 0)
  let loud = @moonlog.Logger::new(Keep::{ seen, }, level=Trace)
  loud.fatal("this one does")
  assert_eq(seen.length(), 1)
}

///|
/// Fields are carried as values, not as text, so a sink decides how they read.
test "fields are values" {
  let (log, held) = capture()
  log.info("listening", fields=[
    ("port", Json::number(8000)),
    ("tls", Json::boolean(false)),
    ("name", Json::string("a b")),
  ])
  // The text sink writes each value as its JSON, so a field with a space in it
  // cannot be mistaken for two fields.
  assert_eq(held[0], "INFO listening port=8000 tls=false name=\"a b\"")
  // And the same record as one object.
  let (structured, lines) = capture(format=@moonlog.json_line)
  structured.info("listening", fields=[
    ("port", Json::number(8000)),
    ("tls", Json::boolean(false)),
  ])
  assert_eq(
    lines[0],
    "{\"level\":\"INFO\",\"msg\":\"listening\",\"port\":8000,\"tls\":false}",
  )
}

///|
/// A field named as one of the two the object writes replaces it rather than
/// appearing twice: an object with a key twice is a document readers disagree
/// about, and the caller naming it meant it.
test "a field can replace the level or the message" {
  let (log, held) = capture(format=@moonlog.json_line)
  log.info("first", fields=[("msg", Json::string("second"))])
  assert_eq(held[0], "{\"level\":\"INFO\",\"msg\":\"second\"}")
  // The keys themselves are a knob, for a pipeline that names them otherwise.
  let record : @moonlog.Record = {
    level: Warning,
    message: "slow",
    fields: [("ms", Json::number(1840))],
  }
  assert_eq(
    @moonlog.object(record, level="severity", message="message"),
    "{\"severity\":\"WARNING\",\"message\":\"slow\",\"ms\":1840}",
  )
  assert_eq(@moonlog.level_key, "level")
  assert_eq(@moonlog.message_key, "msg")
}

///|
/// A level by name, for a configuration file — including the names the other
/// libraries use for the same level.
test "a level reads back from its name" {
  for level in [@moonlog.Level::Trace, Debug, Info, Warning, Error, Fatal] {
    assert_eq(@moonlog.Level::parse(level.name()[:]), Some(level))
    assert_eq(@moonlog.Level::parse(level.name().to_lower()[:]), Some(level))
  }
  assert_eq(@moonlog.Level::parse("warn"), Some(@moonlog.Level::Warning))
  assert_eq(@moonlog.Level::parse("err"), Some(@moonlog.Level::Error))
  assert_eq(@moonlog.Level::parse("critical"), Some(@moonlog.Level::Fatal))
  assert_eq(@moonlog.Level::parse("WaRnInG"), Some(@moonlog.Level::Warning))
  // A typo is `None`, not a verbosity nobody asked for.
  assert_eq(@moonlog.Level::parse("chatty"), None)
  assert_eq(@moonlog.Level::parse(""), None)
  // The ranks are the order the levels are written in.
  assert_true(@moonlog.Level::Trace.rank() < @moonlog.Level::Debug.rank())
  assert_true(@moonlog.Level::Error.rank() < @moonlog.Level::Fatal.rank())
  assert_true(@moonlog.Level::Info < @moonlog.Level::Warning)
}

///|
/// A sink of one's own is the whole point of the seam: this library writes
/// nowhere by itself.
test "a sink of one's own" {
  let seen : Array[@moonlog.Record] = []
  let log = @moonlog.Logger::new(Keep::{ seen, }, level=Trace)
  log.warn("held", fields=[("n", Json::number(1))])
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].level, @moonlog.Level::Warning)
  assert_eq(seen[0].message, "held")
  assert_eq(seen[0].fields[0].0, "n")
}

///|
/// A sink that keeps the records themselves rather than a rendering of them.
struct Keep {
  seen : Array[@moonlog.Record]
}

///|
pub impl @moonlog.Sink for Keep with fn write(self, record) {
  self.seen.push(record)
}
