// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The lines the README and the guide print, pinned here so a change in a
/// default layout or a level label breaks a test before it breaks a page.
test "the quick start writes the two lines the README shows" {
  let lines : Array[String] = []
  let sink = @moonlog.Lines::new(fn(line) { lines.push(line) })
  let hub = @moonlog.Hub::new(clock=fn() { 1_700_000_000_000_000_000L })
  ignore(
    hub.add(
      @moonlog.Slot::new(sink, name="console").layout(
        @moonlog.Pattern::parse(
          "{time:%H:%M:%S%.3f} {level:<5} {target}: {msg}{fields}",
        ),
      ),
    ),
  )
  let log = hub.logger("mirror::sync")
  log.info("starting", fields=[("workers", @moonlog.Value::of_int(4))])
  log.warn("slow", fields=[("took_ms", @moonlog.Value::of_int(1200))])
  assert_eq(lines[0], "22:13:20.000 INFO  mirror::sync: starting workers=4")
  assert_eq(lines[1], "22:13:20.000 WARN  mirror::sync: slow took_ms=1200")
}

///|
/// A map is spread into dotted keys and an error keeps its causes, which is what
/// the fields section of the guide claims.
test "an error and a map read the same way on a line" {
  let lines : Array[String] = []
  let hub = @moonlog.Hub::new(clock=fn() { 1_700_000_000_000_000_000L })
  ignore(
    hub.add(
      @moonlog.Slot::new(
        @moonlog.Lines::new(fn(line) { lines.push(line) }),
        name="console",
      ),
    ),
  )
  hub
  .logger("sync")
  .info("gave up", fields=[
    ("error", @moonlog.Value::of_error(message="connect", causes=["refused"])),
    ("tries", @moonlog.Value::of_int(3)),
    ("req", @moonlog.Value::of_map([("id", @moonlog.Value::of_int(7))])),
  ])
  assert_eq(
    lines[0],
    "2023-11-14 22:13:20.000 INFO  sync: gave up error=connect: refused tries=3 req.id=7",
  )
}

///|
/// A profile is a vocabulary as well as a stream and a level: Python's label is
/// `WARNING`, not `WARN`.
test "a profile writes the level the way its logger does" {
  let lines : Array[String] = []
  let hub = @moonlog.Hub::new(profile=@moonlog.Profile::Python, clock=fn() {
    0L
  })
  ignore(
    hub.add(
      @moonlog.Slot::new(
        @moonlog.Lines::new(fn(line) { lines.push(line) }),
        name="console",
      ),
    ),
  )
  hub.logger("app").warn("careful")
  assert_eq(lines[0], "WARNING:app:careful")
}

///|
/// The filter examples the guide prints: a child target raised above the floor,
/// one silenced outright, and the lowest level the spec admits.
test "a filter names a floor, a child target and an off switch" {
  let quiet = @moonlog.Filter::parse("warn, app=debug, app::net=off")
  assert_eq(quiet.allows(@moonlog.debug, "app::sync"), true)
  assert_eq(quiet.allows(@moonlog.error, "app::net"), false)
  assert_eq(quiet.allows(@moonlog.warn, "other"), true)
  assert_eq(quiet.lowest().unwrap().name(), "debug")
}

///|
/// A preset name stands wherever a pattern does, and answers with the name it
/// was given rather than a template.
test "a pattern preset answers with its own name" {
  assert_eq(@moonlog.Pattern::parse("logback").source(), "logback")
  assert_eq(@moonlog.Pattern::parse("{level} {msg}").source(), "{level} {msg}")
}
