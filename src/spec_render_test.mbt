// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The render cases of the shared specification, generated from
/// `scripts/serlog-cases/render.json` by `scripts/gen_cases.py`: one test per
/// case, named with the case's number. Patterns, presets, logfmt, pretty, the
/// JSON schemas and the filters all come from the same record and identity.
fn spec_identity() -> @moonlog.Identity {
  @moonlog.Identity::of(app="demo", env="prod", instance="n1", host="box")
}

///|
/// A scene with the identity the cases share, seen through `profile`.
fn spec_scene(profile : @moonlog.Profile) -> @moonlog.Scene {
  @moonlog.Scene::new(identity=spec_identity(), profile~)
}

///|
/// Where `needle` first stands in `line`.
fn spec_find(line : String, needle : String) -> Int32? {
  let chars = line.to_array()
  let pattern = needle.to_array()
  if pattern.length() == 0 || pattern.length() > chars.length() {
    return None
  }
  for start in 0..<=(chars.length() - pattern.length()) {
    let mut same = true
    for offset in 0..<pattern.length() {
      if chars[start + offset] != pattern[offset] {
        same = false
      }
    }
    if same {
      return Some(start)
    }
  }
  None
}

///|
/// The value `key` holds in the JSON object `line`, as the text between its
/// colons and the comma or brace that ends it.
fn spec_value(line : String, key : String) -> String? {
  let start = match spec_find(line, "\"" + key + "\":") {
    Some(at) => at + key.length() + 3
    None => return None
  }
  let chars = line.to_array()
  let out = StringBuilder()
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  let mut reading = true
  let mut at = start
  while at < chars.length() && reading {
    let char = chars[at]
    if in_string {
      out.write_char(char)
      if escaped {
        escaped = false
      } else if char == '\\' {
        escaped = true
      } else if char == '"' {
        in_string = false
      }
    } else if char == '"' {
      in_string = true
      out.write_char(char)
    } else if char == '{' || char == '[' {
      depth = depth + 1
      out.write_char(char)
    } else if char == '}' || char == ']' {
      if depth == 0 {
        reading = false
      } else {
        depth = depth - 1
        out.write_char(char)
      }
    } else if char == ',' && depth == 0 {
      reading = false
    } else {
      out.write_char(char)
    }
    at = at + 1
  }
  Some(out.to_string())
}

///|
/// Whether a piece of JSON text is a number.
fn spec_is_number(item : String) -> Bool {
  let chars = item.to_array()
  if chars.length() == 0 {
    return false
  }
  let first = chars[0]
  first == '-' || (first >= '0' && first <= '9')
}

///|
/// Two numbers as the same number, whatever the precision they were written
/// with: a case says `1700000000.0` where a line writes `1700000000.000`.
fn spec_same_number(one : String, other : String) -> Bool {
  fn whole(item : String) -> (String, String) {
    let (sign, body) = if item.has_prefix("-") {
      ("-", item[1:].to_owned())
    } else {
      ("", item)
    }
    match body.find(".") {
      Some(dot) => (sign + body[:dot].to_owned(), body[dot + 1:].to_owned())
      None => (sign + body, "")
    }
  }
  let (one_whole, one_part) = whole(one)
  let (other_whole, other_part) = whole(other)
  let mut one_rest = one_part
  let mut other_rest = other_part
  while one_rest.has_suffix("0") {
    one_rest = one_rest[:one_rest.length() - 1].to_owned()
  }
  while other_rest.has_suffix("0") {
    other_rest = other_rest[:other_rest.length() - 1].to_owned()
  }
  one_whole == other_whole && one_rest == other_rest
}

///|
/// Whether `key` holds `want` in the JSON object `line`. Numbers compare by
/// value; everything else compares as the very text a JSON writer emits.
fn spec_holds(line : String, key : String, want : String) -> Bool {
  match spec_value(line, key) {
    None => false
    Some(got) =>
      if spec_is_number(want) && spec_is_number(got) {
        spec_same_number(got, want)
      } else {
        got == want
      }
  }
}

///|
/// Whether `keys` appear in `line` in this order, each one a key of the object
/// rather than a word inside a value.
fn spec_in_order(line : String, keys : Array[String]) -> Bool {
  let mut last = -1
  for key in keys {
    let at = match spec_find(line, "\"" + key + "\":") {
      Some(at) => at
      None => return false
    }
    if at <= last {
      return false
    }
    last = at
  }
  true
}

///|
test "render.json 1: warn from app::sync" {
  let record = @moonlog.Record::of(
      @moonlog.Level::parse("warn"),
      "app::sync",
      "disk 91% full",
    )
    .located("src/sync.rs", line=12)
    .sets([
      ("mirror", @moonlog.Value::of_str("debian")),
      ("id", @moonlog.Value::of_long(7L)),
    ])
    .stamped(1700000000L * 1_000_000_000L)
  let scene = spec_scene(@moonlog.Profile::Serlog)
  assert_eq(
    @moonlog.Pattern::parse("{time:utc} {level} {target}: {msg}{fields}").render(
      record, scene,
    ),
    "2023-11-14T22:13:20Z WARN app::sync: disk 91% full mirror=debian id=7",
  )
  assert_eq(
    @moonlog.Pattern::parse("{{{level:lower>6}}} {file}:{line}").render(
      record, scene,
    ),
    "{  warn} src/sync.rs:12",
  )
  assert_eq(
    @moonlog.Pattern::parse("{level:<7}|{msg:q}|{fields:q}").render(
      record, scene,
    ),
    "WARN   |\"disk 91% full\"| mirror=debian id=7",
  )
  assert_eq(
    @moonlog.Pattern::parse("{target:>12}|{level:^7}|{msg:.4}").render(
      record, scene,
    ),
    "   app::sync| WARN  |disk",
  )
  assert_eq(
    @moonlog.Pattern::parse("{target:~6} {file:base}").render(record, scene),
    "a::sync sync.rs",
  )
  assert_eq(
    @moonlog.Pattern::parse("{time:unix} {time:unix_ms}").render(record, scene),
    "1700000000 1700000000000",
  )
  assert_eq(
    @moonlog.Pattern::parse("{app}/{env}/{instance}").render(record, scene),
    "demo/prod/n1",
  )
  // The serlog preset.
  assert_true(
    @moonlog.Pattern::parse("serlog")
    .render(record, spec_scene(@moonlog.Profile::Serlog))
    .has_suffix(" WARN  app::sync: disk 91% full mirror=debian id=7"),
  )
  // The tracing preset.
  assert_true(
    @moonlog.Pattern::parse("tracing")
    .render(record, spec_scene(@moonlog.Profile::Tracing))
    .has_suffix("  WARN app::sync: disk 91% full mirror=debian id=7"),
  )
  // The env_logger preset.
  assert_eq(
    @moonlog.Pattern::parse("env_logger").render(
      record,
      spec_scene(@moonlog.Profile::EnvLogger),
    ),
    "[2023-11-14T22:13:20Z WARN  app::sync] disk 91% full",
  )
  // The python preset.
  assert_eq(
    @moonlog.Pattern::parse("python").render(
      record,
      spec_scene(@moonlog.Profile::Python),
    ),
    "WARNING:app::sync:disk 91% full",
  )
  // The logback preset.
  assert_true(
    @moonlog.Pattern::parse("logback")
    .render(record, spec_scene(@moonlog.Profile::Logback))
    .has_suffix("] WARN  app::sync - disk 91% full"),
  )
  // The slog preset.
  assert_true(
    @moonlog.Pattern::parse("slog")
    .render(record, spec_scene(@moonlog.Profile::Slog))
    .has_suffix(" level=WARN msg=\"disk 91% full\" mirror=debian id=7"),
  )
  assert_eq(
    @moonlog.Logfmt::new().render(record, scene),
    "time=2023-11-14T22:13:20Z level=warn target=app::sync msg=\"disk 91% full\" mirror=debian id=7",
  )
  assert_true(
    @moonlog.Pretty::new()
    .render(record, scene)
    .has_suffix(
      " WARN  app::sync disk 91% full\n    mirror = debian\n    id     = 7",
    ),
  )
  assert_eq(
    @moonlog.JsonLine::new(@moonlog.Schema::Serlog).render(record, scene),
    "{\"time\":\"2023-11-14T22:13:20.000Z\",\"level\":\"warn\",\"target\":\"app::sync\",\"msg\":\"disk 91% full\",\"file\":\"src/sync.rs\",\"line\":12,\"mirror\":\"debian\",\"id\":7,\"app\":\"demo\",\"env\":\"prod\",\"instance\":\"n1\"}",
  )
  // The pino schema.
  let pino = @moonlog.JsonLine::new(@moonlog.Schema::parse("pino")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(pino, [
      "level", "time", "pid", "hostname", "mirror", "id", "msg",
    ]),
  )
  assert_true(spec_holds(pino, "level", "40"))
  assert_true(spec_holds(pino, "time", "1700000000000"))
  assert_true(spec_holds(pino, "mirror", "\"debian\""))
  assert_true(spec_holds(pino, "id", "7"))
  assert_true(spec_holds(pino, "msg", "\"disk 91% full\""))
  // The bunyan schema.
  let bunyan = @moonlog.JsonLine::new(@moonlog.Schema::parse("bunyan")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(bunyan, [
      "name", "hostname", "pid", "level", "mirror", "id", "msg", "time", "v",
    ]),
  )
  assert_true(spec_holds(bunyan, "name", "\"demo\""))
  assert_true(spec_holds(bunyan, "level", "40"))
  assert_true(spec_holds(bunyan, "msg", "\"disk 91% full\""))
  assert_true(spec_holds(bunyan, "time", "\"2023-11-14T22:13:20.000Z\""))
  assert_true(spec_holds(bunyan, "v", "0"))
  // The zap schema.
  let zap = @moonlog.JsonLine::new(@moonlog.Schema::parse("zap")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(zap, [
      "level", "ts", "logger", "caller", "msg", "mirror", "id",
    ]),
  )
  assert_true(spec_holds(zap, "level", "\"warn\""))
  assert_true(spec_holds(zap, "ts", "1700000000.0"))
  assert_true(spec_holds(zap, "logger", "\"app::sync\""))
  assert_true(spec_holds(zap, "caller", "\"src/sync.rs:12\""))
  assert_true(spec_holds(zap, "msg", "\"disk 91% full\""))
  // The slog schema.
  let slog = @moonlog.JsonLine::new(@moonlog.Schema::parse("slog")).render(
    record, scene,
  )
  assert_true(spec_in_order(slog, ["time", "level", "msg", "mirror", "id"]))
  assert_true(spec_holds(slog, "level", "\"WARN\""))
  assert_true(spec_holds(slog, "msg", "\"disk 91% full\""))
  assert_true(spec_holds(slog, "mirror", "\"debian\""))
  assert_true(spec_holds(slog, "id", "7"))
  // The structlog schema.
  let structlog = @moonlog.JsonLine::new(@moonlog.Schema::parse("structlog")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(structlog, [
      "event", "mirror", "id", "level", "logger", "timestamp",
    ]),
  )
  assert_true(spec_holds(structlog, "event", "\"disk 91% full\""))
  assert_true(spec_holds(structlog, "level", "\"warn\""))
  assert_true(spec_holds(structlog, "logger", "\"app::sync\""))
  assert_true(
    spec_holds(structlog, "timestamp", "\"2023-11-14T22:13:20.000Z\""),
  )
  // The logstash schema.
  let logstash = @moonlog.JsonLine::new(@moonlog.Schema::parse("logstash")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(logstash, [
      "@timestamp", "@version", "message", "logger_name", "thread_name", "level",
      "level_value", "mirror", "id",
    ]),
  )
  assert_true(spec_holds(logstash, "@version", "\"1\""))
  assert_true(spec_holds(logstash, "message", "\"disk 91% full\""))
  assert_true(spec_holds(logstash, "logger_name", "\"app::sync\""))
  assert_true(spec_holds(logstash, "level", "\"WARN\""))
  assert_true(spec_holds(logstash, "level_value", "30000"))
  // The ecs schema.
  let ecs = @moonlog.JsonLine::new(@moonlog.Schema::parse("ecs")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(ecs, [
      "@timestamp", "log.level", "message", "ecs.version", "log.logger", "log.origin.file.name",
      "log.origin.file.line", "process.pid", "host.hostname", "service.name", "service.environment",
      "service.node.name", "mirror", "id",
    ]),
  )
  assert_true(spec_holds(ecs, "@timestamp", "\"2023-11-14T22:13:20.000Z\""))
  assert_true(spec_holds(ecs, "log.level", "\"warn\""))
  assert_true(spec_holds(ecs, "message", "\"disk 91% full\""))
  assert_true(spec_holds(ecs, "log.logger", "\"app::sync\""))
  assert_true(spec_holds(ecs, "log.origin.file.line", "12"))
  assert_true(spec_holds(ecs, "service.name", "\"demo\""))
  assert_true(spec_holds(ecs, "service.environment", "\"prod\""))
  assert_true(spec_holds(ecs, "service.node.name", "\"n1\""))
  // The gelf schema.
  let gelf = @moonlog.JsonLine::new(@moonlog.Schema::parse("gelf")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(gelf, [
      "version", "host", "short_message", "timestamp", "level", "_target", "_mirror",
    ]),
  )
  assert_true(spec_holds(gelf, "version", "\"1.1\""))
  assert_true(spec_holds(gelf, "short_message", "\"disk 91% full\""))
  assert_true(spec_holds(gelf, "timestamp", "1700000000.0"))
  assert_true(spec_holds(gelf, "level", "4"))
  assert_true(spec_holds(gelf, "_target", "\"app::sync\""))
  assert_true(spec_holds(gelf, "_mirror", "\"debian\""))
  // The otel schema.
  let otel = @moonlog.JsonLine::new(@moonlog.Schema::parse("otel")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(otel, [
      "timestamp", "severity_text", "severity_number", "body", "attributes", "resource",
    ]),
  )
  assert_true(
    spec_holds(otel, "timestamp", "\"2023-11-14T22:13:20.000000000Z\""),
  )
  assert_true(spec_holds(otel, "severity_text", "\"WARN\""))
  assert_true(spec_holds(otel, "severity_number", "13"))
  assert_true(spec_holds(otel, "body", "\"disk 91% full\""))
}

///|
test "render.json 2: error from net" {
  let record = @moonlog.Record::of(
      @moonlog.Level::parse("error"),
      "net",
      "said \"no\"\nthen left",
    )
    .sets([
      ("peer", @moonlog.Value::of_str("10.0.0.1:873")),
      ("note", @moonlog.Value::of_str("")),
    ])
    .stamped(1700000000L * 1_000_000_000L)
  let scene = spec_scene(@moonlog.Profile::Serlog)
  assert_eq(
    @moonlog.Pattern::parse("{level:lower} {msg:q}{fields:q}").render(
      record, scene,
    ),
    "error \"said \\\"no\\\"\\nthen left\" peer=10.0.0.1:873 note=\"\"",
  )
  assert_eq(
    @moonlog.Pattern::parse("{file}:{line}").render(record, scene),
    "?:?",
  )
  assert_eq(
    @moonlog.Logfmt::new().render(record, scene),
    "time=2023-11-14T22:13:20Z level=error target=net msg=\"said \\\"no\\\"\\nthen left\" peer=10.0.0.1:873 note=\"\"",
  )
  assert_eq(
    @moonlog.JsonLine::new(@moonlog.Schema::Serlog).render(record, scene),
    "{\"time\":\"2023-11-14T22:13:20.000Z\",\"level\":\"error\",\"target\":\"net\",\"msg\":\"said \\\"no\\\"\\nthen left\",\"peer\":\"10.0.0.1:873\",\"note\":\"\",\"app\":\"demo\",\"env\":\"prod\",\"instance\":\"n1\"}",
  )
}

///|
test "render.json 3: fatal from db" {
  let record = @moonlog.Record::of(@moonlog.Level::parse("fatal"), "db", "lost")
    .sets([
      ("n", @moonlog.Value::of_long(3L)),
      ("ratio", @moonlog.Value::of_float(0.5)),
      ("ok", @moonlog.Value::of_bool(false)),
      ("none", @moonlog.Value::Null),
      (
        "list",
        @moonlog.Value::of_list([
          @moonlog.Value::of_str("a"),
          @moonlog.Value::of_str("b"),
        ]),
      ),
      (
        "req",
        @moonlog.Value::of_map([
          ("id", @moonlog.Value::of_long(7L)),
          ("path", @moonlog.Value::of_str("/x")),
        ]),
      ),
    ])
    .stamped(1700000000L * 1_000_000_000L)
  let scene = spec_scene(@moonlog.Profile::Serlog)
  assert_eq(
    @moonlog.Pattern::parse("{level} {msg}{fields}").render(record, scene),
    "FATAL lost n=3 ratio=0.5 ok=false none=null list=[a, b] req.id=7 req.path=/x",
  )
  assert_eq(
    @moonlog.Pattern::parse("{level:lower}{fields:q}").render(record, scene),
    "fatal n=3 ratio=0.5 ok=false none=null list=\"[a, b]\" req.id=7 req.path=/x",
  )
  // The python preset.
  assert_eq(
    @moonlog.Pattern::parse("python").render(
      record,
      spec_scene(@moonlog.Profile::Python),
    ),
    "CRITICAL:db:lost",
  )
  // The slog preset.
  assert_true(
    @moonlog.Pattern::parse("slog")
    .render(record, spec_scene(@moonlog.Profile::Slog))
    .has_suffix(
      " level=ERROR+4 msg=lost n=3 ratio=0.5 ok=false none=null list=\"[a, b]\" req.id=7 req.path=/x",
    ),
  )
  assert_eq(
    @moonlog.JsonLine::new(@moonlog.Schema::Serlog).render(record, scene),
    "{\"time\":\"2023-11-14T22:13:20.000Z\",\"level\":\"fatal\",\"target\":\"db\",\"msg\":\"lost\",\"n\":3,\"ratio\":0.5,\"ok\":false,\"none\":null,\"list\":[\"a\",\"b\"],\"req\":{\"id\":7,\"path\":\"/x\"},\"app\":\"demo\",\"env\":\"prod\",\"instance\":\"n1\"}",
  )
}

///|
test "render.json 4: error from sync" {
  let record = @moonlog.Record::of(
      @moonlog.Level::parse("error"),
      "sync",
      "gave up",
    )
    .sets([
      ("error", @moonlog.Value::of_error(message="connect", causes=["refused"])),
      ("tries", @moonlog.Value::of_long(3L)),
    ])
    .stamped(1700000000L * 1_000_000_000L)
  let scene = spec_scene(@moonlog.Profile::Serlog)
  assert_eq(
    @moonlog.Pattern::parse("{msg}: {error}{fields}").render(record, scene),
    "gave up: connect: refused tries=3",
  )
  assert_eq(
    @moonlog.Pattern::parse("{msg}{fields}").render(record, scene),
    "gave up error=connect: refused tries=3",
  )
  assert_eq(
    @moonlog.JsonLine::new(@moonlog.Schema::Serlog).render(record, scene),
    "{\"time\":\"2023-11-14T22:13:20.000Z\",\"level\":\"error\",\"target\":\"sync\",\"msg\":\"gave up\",\"error\":{\"message\":\"connect\",\"causes\":[\"refused\"]},\"tries\":3,\"app\":\"demo\",\"env\":\"prod\",\"instance\":\"n1\"}",
  )
  // The pino schema.
  let pino = @moonlog.JsonLine::new(@moonlog.Schema::parse("pino")).render(
    record, scene,
  )
  assert_true(
    spec_in_order(pino, [
      "level", "time", "pid", "hostname", "err", "tries", "msg",
    ]),
  )
  assert_true(
    spec_holds(
      pino, "err", "{\"message\":\"connect\",\"causes\":[\"refused\"]}",
    ),
  )
}

///|
test "render.json filter 1: warn, app=debug, app::db=trace, app::net=off, noisy" {
  let filter = @moonlog.Filter::parse(
    "warn, app=debug, app::db=trace, app::net=off, noisy",
  )
  assert_true(filter.admits(@moonlog.Level::parse("warn"), "other", ""))
  assert_true(filter.admits(@moonlog.Level::parse("debug"), "app", ""))
  assert_true(filter.admits(@moonlog.Level::parse("debug"), "app::sync", ""))
  assert_true(
    filter.admits(@moonlog.Level::parse("trace"), "app::db::pool", ""),
  )
  assert_true(filter.admits(@moonlog.Level::parse("trace"), "noisy::x", ""))
  assert_false(filter.admits(@moonlog.Level::parse("info"), "other", ""))
  assert_false(filter.admits(@moonlog.Level::parse("trace"), "app::sync", ""))
  assert_false(filter.admits(@moonlog.Level::parse("error"), "app::net", ""))
  assert_false(filter.admits(@moonlog.Level::parse("debug"), "apparent", ""))
}

///|
test "render.json filter 2: off" {
  let filter = @moonlog.Filter::parse("off")
  assert_false(filter.admits(@moonlog.Level::parse("fatal"), "any", ""))
}

///|
test "render.json filter 3: an empty spec" {
  let filter = @moonlog.Filter::parse("")
  assert_true(filter.admits(@moonlog.Level::parse("error"), "x", ""))
  assert_true(filter.admits(@moonlog.Level::parse("fatal"), "x", ""))
  assert_false(filter.admits(@moonlog.Level::parse("warn"), "x", ""))
}

///|
test "render.json filter 4: info,com.acme=debug,com.acme.db=off" {
  let filter = @moonlog.Filter::parse("info,com.acme=debug,com.acme.db=off")
  assert_true(filter.admits(@moonlog.Level::parse("debug"), "com.acme.web", ""))
  assert_true(filter.admits(@moonlog.Level::parse("info"), "org.x", ""))
  assert_false(filter.admits(@moonlog.Level::parse("debug"), "org.x", ""))
  assert_false(
    filter.admits(@moonlog.Level::parse("error"), "com.acme.db.pool", ""),
  )
  assert_false(filter.admits(@moonlog.Level::parse("debug"), "com.acmex", ""))
}

///|
test "render.json filter 5: warn,web:*=error,app=debug" {
  let filter = @moonlog.Filter::parse("warn,web:*=error,app=debug")
  assert_true(filter.admits(@moonlog.Level::parse("error"), "web:api", ""))
  assert_true(filter.admits(@moonlog.Level::parse("debug"), "app::x", ""))
  assert_true(filter.admits(@moonlog.Level::parse("warn"), "other", ""))
  assert_false(filter.admits(@moonlog.Level::parse("warn"), "web:api", ""))
  assert_false(filter.admits(@moonlog.Level::parse("info"), "other", ""))
}

///|
test "render.json filter 6: 35" {
  let filter = @moonlog.Filter::parse("35")
  assert_true(filter.admits(@moonlog.Level::parse("warn"), "x", ""))
  assert_false(filter.admits(@moonlog.Level::parse("info"), "x", ""))
}

///|
test "render.json filter 7: info,app=fatal" {
  let filter = @moonlog.Filter::parse("info,app=fatal")
  assert_true(filter.admits(@moonlog.Level::parse("fatal"), "app", ""))
  assert_false(filter.admits(@moonlog.Level::parse("error"), "app", ""))
}

///|
test "render.json filter 8: info/sync(ed)?" {
  let filter = @moonlog.Filter::parse("info/sync(ed)?")
  assert_true(
    filter.admits(@moonlog.Level::parse("info"), "x", "synced 3 files"),
  )
}
