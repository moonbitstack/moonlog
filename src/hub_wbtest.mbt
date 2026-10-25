// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink that fails while `broken` is set, and remembers what got through.
struct Flaky {
  mut broken : Bool
  lines : Array[String]
}

///|
fn Flaky::new() -> Flaky {
  { broken: false, lines: [], }
}

///|
pub impl Sink for Flaky with fn write(self, entry) {
  if self.broken {
    Err("connection refused")
  } else {
    self.lines.push(entry.line)
    Ok(())
  }
}

///|
pub extend Flaky with Sink::{write}

///|
fn clock_at(n : Int64) -> () -> Int64 {
  fn() { n }
}

///|
test "a logger writes what its hub lets through" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(1_700_000_000_000_000_000L))
  ignore(hub.add(Slot::new(sink, name="mem")))
  let log = hub.logger("app::sync")
  log.info("listening", fields=[("port", Value::of_int(8000))])
  log.debug("hidden below info")
  assert_eq(
    join(sink.lines(), "\n"),
    "2023-11-14 22:13:20.000 INFO  app::sync: listening port=8000",
  )
}

///|
test "the hub's filter decides once, for every slot" {
  let sink = Memory::new()
  let hub = Hub::new(
    clock=clock_at(0L),
    filter=Some(Filter::parse("warn,app=debug")),
  )
  ignore(hub.add(Slot::new(sink, name="mem")))
  let log = hub.logger("app::sync")
  log.debug("seen")
  log.warn("seen")
  hub.logger("other").warn("seen")
  hub.logger("other").info("gone")
  assert_eq(
    join(sink.lines(), "\n"),
    "1970-01-01 00:00:00.000 DEBUG app::sync: seen\n" +
    "1970-01-01 00:00:00.000 WARN  app::sync: seen\n" +
    "1970-01-01 00:00:00.000 WARN  other: seen",
  )
}

///|
test "a slot's own filter narrows what reaches its sink" {
  let all = Memory::new()
  let errors = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  ignore(hub.add(Slot::new(all, name="all")))
  ignore(hub.add(Slot::new(errors, name="errors").at(error)))
  let log = hub.logger("app")
  log.info("steady")
  log.error("broke")
  assert_eq(all.lines().length(), 2)
  assert_eq(errors.lines().length(), 1)
  assert_true(errors.lines()[0].contains(("broke" : StringView)))
}

///|
test "fields bound to a logger come before the call's own" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  ignore(hub.add(Slot::new(sink, name="mem").layout(Logfmt::new())))
  let log = hub.logger("req").bound("id", Value::of_str("r-1"))
  log.info("handled", fields=[("path", Value::of_str("/x"))])
  let line = sink.lines()[0]
  assert_true(line.contains(("id=r-1" : StringView)))
  assert_true(line.contains(("path=/x" : StringView)))
  assert_true(
    line.find(("id=r-1" : StringView)).unwrap() <
    line.find(("path=/x" : StringView)).unwrap(),
  )
}

///|
test "a second slot with the same name is refused" {
  let hub = Hub::new()
  ignore(hub.add(Slot::new(Memory::new(), name="mem")))
  let refused = try {
    let _ = hub.add(Slot::new(Memory::new(), name="mem"))
    None
  } catch {
    e => Some(e)
  }
  assert_true(refused is Some(_))
}

///|
test "redaction masks by name, by path and in the message, without touching the original" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  let redact = Redact::new()
    .key("token")
    .path("req.headers.auth")
    .pattern("[0-9]{3}-[0-9]{4}")
  ignore(
    hub.add(Slot::new(sink, name="mem").layout(Logfmt::new()).process(redact)),
  )
  let log = hub.logger("auth")
  log.info("call 555-1234", fields=[
    ("token", Value::of_str("secret")),
    (
      "req",
      Value::of_map([
        ("headers", Value::of_map([("auth", Value::of_str("Bearer x"))])),
      ]),
    ),
  ])
  let line = sink.lines()[0]
  assert_true(line.contains(("msg=\"call ***\"" : StringView)))
  assert_true(line.contains(("token=***" : StringView)))
  assert_true(line.contains(("req.headers.auth=***" : StringView)))
}

///|
test "sanitise escapes the line break a message tried to smuggle in" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  ignore(
    hub.add(
      Slot::new(sink, name="mem").layout(Logfmt::new()).process(Sanitise::new()),
    ),
  )
  hub.logger("net").info("said \"no\"\nthen left")
  assert_true(
    sink.lines()[0].contains(
      ("msg=\"said \\\"no\\\"\\\\nthen left\"" : StringView),
    ),
  )
}

///|
test "keep and exclude decide on tags, fields and level" {
  let kept = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  let only_audit = Match::new().tag("audit")
  ignore(hub.add(Slot::new(kept, name="audit").process(only_audit)))
  let log = hub.logger("app")
  log.info("quiet")
  let record = Record::of(info, "app", "louder").tag("audit")
  hub.dispatch(record)
  assert_eq(kept.lines().length(), 1)
  assert_true(kept.lines()[0].contains(("louder" : StringView)))
  let quiet = Memory::new()
  ignore(
    hub.add(Slot::new(quiet, name="quiet").process(Exclude::new().tag("audit"))),
  )
  hub.dispatch(record)
  assert_eq(quiet.lines().length(), 0)
}

///|
test "sample keeps the first of a burst and one in so many after" {
  let sample = Sample::new(first=2, every=2, per=1_000_000_000L)
  let record = Record::of(info, "app", "tick")
  let kept : Array[Int32] = []
  for i in 0..<6 {
    match sample.process(record, Env::at(0L)) {
      Some(_) => kept.push(i)
      None => ()
    }
  }
  assert_eq(join(kept.map(fn(i) { i.to_string() }), ","), "0,1,3,5")
}

///|
test "limit lets a burst through and then one a second" {
  let limit = Limit::new(rate=1.0, burst=2.0)
  let record = Record::of(info, "app", "tick")
  let mut allowed = 0
  for _ in 0..<3 {
    if limit.process(record, Env::at(0L)) is Some(_) {
      allowed = allowed + 1
    }
  }
  assert_eq(allowed, 2)
  assert_true(limit.process(record, Env::at(500_000_000L)) is None)
  assert_true(limit.process(record, Env::at(1_000_000_000L)) is Some(_))
}

///|
test "dedupe drops repeats and counts them on the next one kept" {
  let dedupe = Dedupe::new(within=1_000_000_000L)
  let record = Record::of(warn, "app", "disk full")
  assert_true(dedupe.process(record, Env::at(0L)) is Some(_))
  assert_true(dedupe.process(record, Env::at(100L)) is None)
  assert_true(dedupe.process(record, Env::at(200L)) is None)
  match dedupe.process(record, Env::at(2_000_000_000L)) {
    Some(kept) => assert_true(kept.field("repeated") is Some(Value::Int(2L)))
    None => fail("the next one within the window is kept")
  }
}

///|
test "a queued slot writes in batches and a flush empties it" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  ignore(
    hub.add(Slot::new(sink, name="mem").queue(Queue::new(size=10).batch(3))),
  )
  let log = hub.logger("app")
  log.info("one")
  log.info("two")
  assert_eq(sink.lines().length(), 0)
  log.info("three")
  assert_eq(sink.lines().length(), 3)
  log.info("four")
  assert_eq(sink.lines().length(), 3)
  hub.flush()
  assert_eq(sink.lines().length(), 4)
}

///|
test "a failing sink goes down, is skipped, and recovers at its probe" {
  let now = [0L]
  let hub = Hub::new(clock=fn() { now[0] })
  let flaky = Flaky::new()
  ignore(hub.add(Slot::new(flaky, name="flaky")))
  let log = hub.logger("app")
  flaky.broken = true
  log.info("first")
  assert_true(hub.status()[0].health == Down)
  now[0] = 1_000_000_000L
  log.info("skipped")
  assert_eq(hub.status()[0].skipped, 1L)
  flaky.broken = false
  now[0] = 6_000_000_000L
  log.info("back")
  assert_true(hub.status()[0].health == Up)
  assert_eq(flaky.lines.length(), 1)
}

///|
test "an alarm takes the incident to another slot, and the failing one is not asked" {
  let now = [0L]
  let hub = Hub::new(clock=fn() { now[0] })
  let flaky = Flaky::new()
  let backup = Memory::new()
  let oncall = Tiers::from([["backup"]])
  ignore(hub.add(Slot::new(flaky, name="flaky").on_fail(OnFail::Alarm(oncall))))
  ignore(hub.add(Slot::new(backup, name="backup").layout(Logfmt::new())))
  flaky.broken = true
  hub.logger("app").info("first")
  let incidents = backup.find("phase=opened")
  assert_eq(incidents.length(), 1)
  assert_true(incidents[0].line.contains(("level=error" : StringView)))
  assert_true(incidents[0].line.contains(("sink `flaky` failed" : StringView)))
  assert_eq(flaky.lines.length(), 0)
  now[0] = 6_000_000_000L
  flaky.broken = false
  hub.logger("app").info("back")
  let recovered = backup.find("phase=resolved")
  assert_eq(recovered.length(), 1)
  assert_true(recovered[0].line.contains(("level=info" : StringView)))
}

///|
test "a slot kept for alarms only is off the log route" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  ignore(hub.add(Slot::new(sink, name="oncall").alarm_only()))
  hub.logger("app").info("hello")
  assert_eq(sink.lines().length(), 0)
}

///|
test "a hub's global chain runs before any slot" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  hub.process(Fields::new().set("region", Value::of_str("cn")))
  ignore(hub.add(Slot::new(sink, name="mem").layout(Logfmt::new())))
  hub.logger("app").info("hello")
  assert_true(sink.lines()[0].contains(("region=cn" : StringView)))
}

///|
test "an application can colour a slot's lines" {
  let sink = Memory::new()
  let hub = Hub::new(clock=clock_at(0L))
  ignore(hub.add(Slot::new(sink, name="mem").coloured(true).at(warn)))
  hub.logger("app").warn("careful")
  assert_true(sink.lines()[0].contains(("\u{1b}[33m" : StringView)))
}
