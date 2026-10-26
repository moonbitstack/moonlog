///|
fn scene() -> @moonlog.Scene {
  @moonlog.Scene::new(
    identity=@moonlog.Identity::of(
      app="demo",
      host="box",
      pid=42,
      start=1_700_000_000_000_000_000L,
    ),
    profile=@moonlog.Profile::Serlog,
  )
}

///|
fn record() -> @moonlog.Record {
  @moonlog.Record::of(@moonlog.warn, "app::sync", "disk full")
  .set("mirror", @moonlog.Value::of_str("debian"))
  .stamped(1_700_000_001_500_000_000L)
  .numbered(7L)
}

///|
test "every schema reads back from its name" {
  let names = [
    "serlog", "pino", "bunyan", "zap", "slog", "structlog", "logstash", "ecs", "gelf",
    "otel",
  ]
  for name in names {
    assert_eq(@moonlog.Schema::parse(name).name(), name)
  }
  let refused = try {
    ignore(@moonlog.Schema::parse("xml"))
    false
  } catch {
    @moonlog.Refused(got~, ..) => got == "xml"
  }
  assert_eq(refused, true)
  ignore(@moonlog.Levels::parse("name"))
  ignore(@moonlog.Levels::parse("number"))
  let levels = try {
    ignore(@moonlog.Levels::parse("words"))
    false
  } catch {
    @moonlog.Refused(..) => true
  }
  assert_eq(levels, true)
}

///|
test "a JSON line renames keys, writes levels either way, and nests fields" {
  let plain = @moonlog.JsonLine::new(@moonlog.Schema::parse("serlog"))
  let renamed = plain.rename("msg", "message").render(record(), scene())
  assert_eq(renamed.contains("\"message\":\"disk full\""), true)
  assert_eq(renamed.contains("\"msg\""), false)
  let numbered = @moonlog.JsonLine::new(@moonlog.Schema::parse("serlog"))
    .levels(@moonlog.Levels::parse("number"))
    .render(record(), scene())
  assert_eq(numbered.contains("\"level\":40"), true)
  let named = @moonlog.JsonLine::new(@moonlog.Schema::parse("pino"))
    .levels(@moonlog.Levels::parse("name"))
    .render(record(), scene())
  assert_eq(named.contains("\"level\":\"warn\""), true)
  let bunyan = @moonlog.JsonLine::new(@moonlog.Schema::parse("bunyan"))
    .levels(@moonlog.Levels::parse("name"))
    .render(record(), scene())
  assert_eq(bunyan.contains("\"level\":\"warn\""), true)
  let nested = @moonlog.JsonLine::new(@moonlog.Schema::parse("serlog"))
    .nest("ctx")
    .render(record(), scene())
  assert_eq(nested.contains("\"ctx\":{\"mirror\":\"debian\"}"), true)
  let logstash = @moonlog.JsonLine::new(@moonlog.Schema::parse("logstash"))
    .levels(@moonlog.Levels::parse("number"))
    .render(record(), scene())
  assert_eq(logstash.contains("30000"), true)
}

///|
test "pattern tokens for the caller, the identity, tags, spans and counters" {
  let r = record().tag("audit").tag("disk")
  r.caller = {
    module_path: Some("app/sync"),
    func: Some("run"),
    file: None,
    line: None,
  }
  r.spans = Some("job:step")
  let p = @moonlog.Pattern::parse(
    "{module} {func} {tid} {task} {pid} {host} [{tags}] {elapsed} #{seq} {spans}{msg}",
  )
  assert_eq(
    p.render(r, scene()),
    "app/sync run ? ? 42 box [audit,disk] 1500 #7 job:step: disk full",
  )
  let bare = record()
  let q = @moonlog.Pattern::parse("{module}|{func}|{thread}|{tags}|{spans}end")
  assert_eq(q.render(bare, scene()), "app::sync|?|?||end")
  assert_eq(q.source(), "{module}|{func}|{thread}|{tags}|{spans}end")
}

///|
test "a pattern refuses an unclosed hole and a bad precision" {
  let unclosed = try {
    ignore(@moonlog.Pattern::parse("{msg"))
    false
  } catch {
    @moonlog.Refused(at~, ..) => at == 0
  }
  assert_eq(unclosed, true)
  let precision = try {
    ignore(@moonlog.Pattern::parse("{msg:.x}"))
    false
  } catch {
    @moonlog.Refused(..) => true
  }
  assert_eq(precision, true)
}

///|
test "logfmt and pretty construct and render" {
  let line = @moonlog.Logfmt::new().render(record(), scene())
  assert_eq(line.contains("msg=\"disk full\""), true)
  assert_eq(line.contains("mirror=debian"), true)
  let pretty = @moonlog.Pretty::new().render(record(), scene())
  assert_eq(pretty.contains("mirror = debian"), true)
}
