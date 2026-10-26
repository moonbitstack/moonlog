///|
test "every colour has an escape and a name that reads back" {
  let all = [
    @moonlog.Plain,
    @moonlog.Red,
    @moonlog.Green,
    @moonlog.Yellow,
    @moonlog.Blue,
    @moonlog.Magenta,
    @moonlog.Cyan,
    @moonlog.White,
    @moonlog.Grey,
    @moonlog.Alarm,
  ]
  let escapes = all.map(c => c.ansi())
  assert_eq(escapes, [
    "", "\u{1b}[1;31m", "\u{1b}[32m", "\u{1b}[33m", "\u{1b}[34m", "\u{1b}[35m", "\u{1b}[36m",
    "\u{1b}[37m", "\u{1b}[90m", "\u{1b}[1;37;41m",
  ])
  for c in all {
    assert_eq(@moonlog.Colour::parse(c.name()).name(), c.name())
  }
  assert_eq(@moonlog.Colour::parse("gray").name(), "grey")
  assert_eq(@moonlog.reset, "\u{1b}[0m")
}

///|
test "an unknown colour is refused" {
  let refused = try {
    ignore(@moonlog.Colour::parse("mauve"))
    false
  } catch {
    @moonlog.Refused(got~, ..) => got == "mauve"
  }
  assert_eq(refused, true)
}

///|
test "every profile reads back from its name and states its defaults" {
  let names = [
    "serlog", "tracing", "env_logger", "python", "logback", "slog", "pino",
  ]
  for name in names {
    assert_eq(@moonlog.Profile::parse(name).name(), name)
  }
  assert_eq(@moonlog.Profile::parse("log4j").name(), "logback")
  let streams = names.map(n => {
    @moonlog.Profile::parse(n).stream().name().to_owned()
  })
  assert_eq(streams, [
    "stdout", "stdout", "stderr", "stderr", "stdout", "stdout", "stdout",
  ])
  let levels = names.map(n => @moonlog.Profile::parse(n).level().name())
  assert_eq(levels, ["info", "info", "error", "warn", "debug", "info", "info"])
  let envs = names.map(n => @moonlog.Profile::parse(n).env())
  assert_eq(envs, [
    ["SERLOG_FILTER"],
    ["RUST_LOG"],
    ["RUST_LOG"],
    [],
    [],
    [],
    [],
  ])
  assert_eq(
    @moonlog.Profile::parse("pino").pattern().to_owned(),
    "[{time:%H:%M:%S%.3f}] {level} ({pid}): {msg}{fields}",
  )
  for name in names {
    ignore(@moonlog.Pattern::parse(@moonlog.Profile::parse(name).pattern()))
  }
}

///|
test "streams read back from their names, and nothing else does" {
  for name in ["stdout", "stderr", "auto"] {
    assert_eq(@moonlog.Stream::parse(name).name(), name)
  }
  let refused = try {
    ignore(@moonlog.Stream::parse("stdin"))
    false
  } catch {
    @moonlog.Refused(..) => true
  }
  assert_eq(refused, true)
  let unknown = try {
    ignore(@moonlog.Profile::parse("syslog"))
    false
  } catch {
    @moonlog.Refused(got~, ..) => got == "syslog"
  }
  assert_eq(unknown, true)
}

///|
test "levels number themselves for syslog, Logstash and OpenTelemetry" {
  let levels = @moonlog.built_in()
  assert_eq(levels.map(l => l.value()), [10, 20, 30, 40, 50, 60])
  assert_eq(levels.map(l => l.syslog()), [7, 7, 6, 4, 3, 2])
  assert_eq(levels.map(l => l.logstash()), [
    5000, 10000, 20000, 30000, 40000, 40000,
  ])
  assert_eq(levels.map(l => l.otel()), [1, 5, 9, 13, 17, 21])
  assert_eq(levels.map(l => l.colour().name().to_owned()).length(), 6)
  assert_eq(levels.map(l => l.to_string()), [
    "trace", "debug", "info", "warn", "error", "fatal",
  ])
}

///|
test "labels follow the profile in force" {
  let python = @moonlog.Profile::parse("python")
  let slog = @moonlog.Profile::parse("slog")
  let serlog = @moonlog.Profile::parse("serlog")
  assert_eq(@moonlog.warn.label(python), "WARNING")
  assert_eq(@moonlog.fatal.label(python), "CRITICAL")
  assert_eq(@moonlog.fatal.label(slog), "ERROR+4")
  assert_eq(@moonlog.trace.label(slog), "DEBUG-4")
  assert_eq(@moonlog.fatal.label(serlog), "FATAL")
  assert_eq(@moonlog.trace.label(serlog), "TRACE")
  assert_eq(@moonlog.Level::parse("35").label(serlog), "35")
}

///|
test "levels compare by value and parse by name or number" {
  assert_eq(@moonlog.warn > @moonlog.info, true)
  assert_eq(@moonlog.warn >= @moonlog.warn, true)
  assert_eq(@moonlog.debug < @moonlog.info, true)
  assert_eq(@moonlog.error <= @moonlog.debug, false)
  assert_eq(@moonlog.info.compare(@moonlog.info), 0)
  assert_eq(@moonlog.Level::parse("WARNING").name(), "warn")
  assert_eq(@moonlog.Level::parse("err").name(), "error")
  assert_eq(@moonlog.Level::parse("Critical").name(), "fatal")
  assert_eq(@moonlog.Level::parse("255").value(), 255)
  let refused = try {
    ignore(@moonlog.Level::parse("256"))
    false
  } catch {
    @moonlog.Refused(..) => true
  }
  assert_eq(refused, true)
  let empty = try {
    ignore(@moonlog.Level::parse(""))
    false
  } catch {
    @moonlog.Refused(..) => true
  }
  assert_eq(empty, true)
}

///|
test "values write themselves as text and as JSON" {
  let map = @moonlog.Value::of_map([
    ("a", @moonlog.Value::of_int(1)),
    (
      "b",
      @moonlog.Value::of_list([
        @moonlog.Value::of_bool(true),
        @moonlog.Value::of_null(),
      ]),
    ),
  ])
  assert_eq(map.to_text(), "{a=1, b=[true, null]}")
  assert_eq(map.encode(), "{\"a\":1,\"b\":[true,null]}")
  assert_eq(@moonlog.Value::of_bool(false).encode(), "false")
  assert_eq(@moonlog.Value::of_long(1L << 40).encode(), "1099511627776")
  assert_eq(@moonlog.Value::of_other("<x>").to_text(), "<x>")
  assert_eq(@moonlog.Value::of_other("<x>").encode(), "\"<x>\"")
  assert_eq(
    @moonlog.Value::of_error(message="connect", causes=["refused", "timeout"]).encode(),
    "{\"message\":\"connect\",\"causes\":[\"refused\",\"timeout\"]}",
  )
  assert_eq(@moonlog.Value::of_float(1.5).encode(), "1.5")
  assert_eq(@moonlog.Value::of_float(1.0 / 0.0).encode(), "\"Infinity\"")
  assert_eq(@moonlog.Value::of_float(0.0 / 0.0).encode(), "\"NaN\"")
  assert_eq(@moonlog.Value::of_float(0.0 / 0.0).encode(), "\"NaN\"")
  assert_eq(
    @moonlog.Value::of_str("tab\there\r\u{1}").encode(),
    "\"tab\\there\\r\\u0001\"",
  )
  assert_eq(@moonlog.Value::of_str("\u{1f}").encode(), "\"\\u001f\"")
  let out = StringBuilder()
  @moonlog.Value::of_str("q\"").write_json(out)
  assert_eq(out.to_string(), "\"q\\\"\"")
}

///|
test "clocks write every form, before 1970 as well" {
  let t = 1_700_000_000_123_456_789L
  let write = fn(clock : @moonlog.Clock, time : Int64, offset : Int32) {
    let out = StringBuilder()
    clock.write(out, time, offset)
    out.to_string()
  }
  assert_eq(write(@moonlog.Clock::parse("unix"), t, 0), "1700000000")
  assert_eq(write(@moonlog.Clock::parse("unix_ms"), t, 0), "1700000000123")
  assert_eq(
    write(@moonlog.Clock::parse("unix_ns"), t, 0),
    "1700000000123456789",
  )
  assert_eq(write(@moonlog.Clock::parse("unix"), -1L, 0), "-1")
  assert_eq(write(@moonlog.Clock::parse("unix_ms"), -1_500_000L, 0), "-2")
  assert_eq(write(@moonlog.Clock::parse("%Y-%m-%e"), t, 0), "2023-11-14")
  assert_eq(
    write(@moonlog.Clock::parse("%e"), 1_699_142_400_000_000_000L, 0),
    " 5",
  )
  assert_eq(
    write(@moonlog.Clock::parse("%z"), t, -(5 * 3600 + 30 * 60)),
    "-0530",
  )
  assert_eq(write(@moonlog.Clock::parse("%z"), t, 3600), "+0100")
  assert_eq(write(@moonlog.Clock::parse("%:z"), t, 3600), "+01:00")
  assert_eq(write(@moonlog.Clock::parse("100%%"), t, 0), "100%")
  assert_eq(write(@moonlog.Clock::parse("%q"), t, 0), "%q")
  assert_eq(write(@moonlog.Clock::parse("end%"), t, 0), "end%")
  assert_eq(write(@moonlog.Clock::parse("%.3f"), t, 0), ".123")
  assert_eq(write(@moonlog.Clock::parse("%f"), t, 0), ".123456789")
}
