// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The render vectors of the shared specification: patterns, presets, logfmt,
/// pretty, JSON and its schemas, all from the same record and identity.
fn render_scene() -> Scene {
  Scene::new(
    identity=Identity::of(app="demo", env="prod", instance="n1", host="box"),
    profile=Profile::Serlog,
  )
}

///|
fn render_record() -> Record {
  Record::of(warn, "app::sync", "disk 91% full")
  .sets([("mirror", Value::of_str("debian")), ("id", Value::of_int(7))])
  .located("src/sync.rs", line=12)
  .stamped(1_700_000_000_000_000_000L)
}

///|
test "patterns render the usual line" {
  let record = render_record()
  let scene = render_scene()
  let cases = [
    (
      "{time:utc} {level} {target}: {msg}{fields}", "2023-11-14T22:13:20Z WARN app::sync: disk 91% full mirror=debian id=7",
    ),
    ("{{{level:lower>6}}} {file}:{line}", "{  warn} src/sync.rs:12"),
    (
      "{level:<7}|{msg:q}|{fields:q}", "WARN   |\"disk 91% full\"| mirror=debian id=7",
    ),
    ("{target:>12}|{level:^7}|{msg:.4}", "   app::sync| WARN  |disk"),
    ("{target:~6} {file:base}", "a::sync sync.rs"),
    ("{time:unix} {time:unix_ms}", "1700000000 1700000000000"),
    ("{app}/{env}/{instance}", "demo/prod/n1"),
  ]
  for (text, want) in cases {
    let pattern = Pattern::parse(text)
    let got = pattern.render(record, scene)
    assert_eq(got, want)
  }
}

///|
test "presets end the way their logger ends a line" {
  let record = render_record()
  let scene = render_scene()
  let cases = [
    ("serlog", " WARN  app::sync: disk 91% full mirror=debian id=7"),
    ("tracing", "  WARN app::sync: disk 91% full mirror=debian id=7"),
    ("env_logger", "[2023-11-14T22:13:20Z WARN  app::sync] disk 91% full"),
    ("python", "WARNING:app::sync:disk 91% full"),
    ("logback", "] WARN  app::sync - disk 91% full"),
    ("slog", " level=WARN msg=\"disk 91% full\" mirror=debian id=7"),
  ]
  for (name, tail) in cases {
    let pattern = Pattern::parse(name)
    let got = pattern.render(record, scene)
    assert_true(got.has_suffix(tail))
  }
}

///|
test "logfmt and pretty" {
  let record = render_record()
  let scene = render_scene()
  assert_eq(
    Logfmt::new().render(record, scene),
    "time=2023-11-14T22:13:20Z level=warn target=app::sync msg=\"disk 91% full\" mirror=debian id=7",
  )
  assert_true(
    Pretty::new()
    .render(record, scene)
    .has_suffix(
      " WARN  app::sync disk 91% full\n    mirror = debian\n    id     = 7",
    ),
  )
}

///|
test "the default JSON schema" {
  let record = render_record()
  let scene = render_scene()
  assert_eq(
    JsonLine::new(Schema::Serlog).render(record, scene),
    "{\"time\":\"2023-11-14T22:13:20.000Z\",\"level\":\"warn\",\"target\":\"app::sync\"," +
    "\"msg\":\"disk 91% full\",\"file\":\"src/sync.rs\",\"line\":12,\"mirror\":\"debian\"," +
    "\"id\":7,\"app\":\"demo\",\"env\":\"prod\",\"instance\":\"n1\"}",
  )
}

///|
test "ten schemas keep the keys their tools expect" {
  let record = render_record().on("main")
  let scene = render_scene()
  let cases = [
    ("pino", "level,time,pid,hostname,mirror,id,msg"),
    ("bunyan", "name,hostname,pid,level,mirror,id,msg,time,v"),
    ("zap", "level,ts,logger,caller,msg,mirror,id"),
    ("slog", "time,level,msg,mirror,id"),
    ("structlog", "event,mirror,id,level,logger,timestamp"),
    (
      "logstash", "@timestamp,@version,message,logger_name,thread_name,level,level_value,mirror,id",
    ),
    (
      "ecs",
      "@timestamp,log.level,message,ecs.version,log.logger,log.origin.file.name," +
      "log.origin.file.line,process.pid,host.hostname,service.name,service.environment," +
      "service.node.name,mirror,id",
    ),
    ("gelf", "version,host,short_message,timestamp,level,_target,_mirror"),
    ("otel", "timestamp,severity_text,severity_number,body,attributes,resource"),
  ]
  for (name, keys) in cases {
    let schema = Schema::parse(name)
    let json = JsonLine::new(schema).render(record, scene)
    assert_eq(join(top_keys(json), ","), keys)
    // A timestamp is a string in every one of them; a bare `2023` would be a
    // document no reader accepts.
    assert_false(json.contains(("\":2" : StringView)))
  }
  let pino = JsonLine::new(Schema::Pino).render(record, scene)
  assert_true(pino.contains(("\"level\":40" : StringView)))
  assert_true(pino.contains(("\"time\":1700000000000" : StringView)))
  let zap = JsonLine::new(Schema::Zap).render(record, scene)
  assert_true(zap.contains(("\"caller\":\"src/sync.rs:12\"" : StringView)))
  let gelf = JsonLine::new(Schema::Gelf).render(record, scene)
  assert_true(gelf.contains(("\"level\":4" : StringView)))
  let otel = JsonLine::new(Schema::Otel).render(record, scene)
  assert_true(otel.contains(("\"severity_number\":13" : StringView)))
  assert_true(
    otel.contains(
      ("\"timestamp\":\"2023-11-14T22:13:20.000000000Z\"" : StringView),
    ),
  )
}

///|
test "a message with quotes and a line break keeps its shape" {
  let record = Record::of(error, "net", "said \"no\"\nthen left")
    .sets([("peer", Value::of_str("10.0.0.1:873")), ("note", Value::of_str(""))])
    .stamped(1_700_000_000_000_000_000L)
  let scene = render_scene()
  assert_eq(
    Pattern::parse("{level:lower} {msg:q}{fields:q}").render(record, scene),
    "error \"said \\\"no\\\"\\nthen left\" peer=10.0.0.1:873 note=\"\"",
  )
  assert_eq(Pattern::parse("{file}:{line}").render(record, scene), "?:?")
  assert_eq(
    Logfmt::new().render(record, scene),
    "time=2023-11-14T22:13:20Z level=error target=net " +
    "msg=\"said \\\"no\\\"\\nthen left\" peer=10.0.0.1:873 note=\"\"",
  )
  assert_true(
    JsonLine::new(Schema::Serlog)
    .render(record, scene)
    .contains(("\"msg\":\"said \\\"no\\\"\\nthen left\"" : StringView)),
  )
}

///|
test "typed values keep their type" {
  let record = Record::of(fatal, "db", "lost")
    .sets([
      ("n", Value::of_int(3)),
      ("ratio", Value::of_float(0.5)),
      ("ok", Value::of_bool(false)),
      ("none", Value::of_null()),
      ("list", Value::of_list([Value::of_str("a"), Value::of_str("b")])),
      (
        "req",
        Value::of_map([("id", Value::of_int(7)), ("path", Value::of_str("/x"))]),
      ),
    ])
    .stamped(1_700_000_000_000_000_000L)
  let scene = render_scene()
  assert_eq(
    Pattern::parse("{level} {msg}{fields}").render(record, scene),
    "FATAL lost n=3 ratio=0.5 ok=false none=null list=[a, b] req.id=7 req.path=/x",
  )
  assert_eq(
    Pattern::parse("{level:lower}{fields:q}").render(record, scene),
    "fatal n=3 ratio=0.5 ok=false none=null list=\"[a, b]\" req.id=7 req.path=/x",
  )
  assert_eq(Pattern::parse("python").render(record, scene), "CRITICAL:db:lost")
  let json = JsonLine::new(Schema::Serlog).render(record, scene)
  assert_true(json.contains(("\"list\":[\"a\",\"b\"]" : StringView)))
  assert_true(
    json.contains(("\"req\":{\"id\":7,\"path\":\"/x\"}" : StringView)),
  )
}

///|
test "an error field travels as one field, not as text inside the fields" {
  let record = Record::of(error, "sync", "gave up")
    .sets([
      ("error", Value::of_error(message="connect", causes=["refused"])),
      ("tries", Value::of_int(3)),
    ])
    .stamped(1_700_000_000_000_000_000L)
  let scene = render_scene()
  assert_eq(
    Pattern::parse("{msg}: {error}{fields}").render(record, scene),
    "gave up: connect: refused tries=3",
  )
  assert_eq(
    Pattern::parse("{msg}{fields}").render(record, scene),
    "gave up error=connect: refused tries=3",
  )
  let json = JsonLine::new(Schema::Serlog).render(record, scene)
  assert_true(
    json.contains(
      (
        "\"error\":{\"message\":\"connect\",\"causes\":[\"refused\"]}" :
        StringView),
    ),
  )
  let pino = JsonLine::new(Schema::Pino).render(record, scene)
  assert_true(
    pino.contains(
      ("\"err\":{\"message\":\"connect\",\"causes\":[\"refused\"]}" : StringView),
    ),
  )
}

///|
test "a pattern that does not parse is refused, and says where" {
  for
    bad in [
      "{nope}", "{level:%5}", "{msg:x}", "a } b", "{level:<x}", "{target:~x}",
    ] {
    let refused = try {
      let _ = Pattern::parse(bad)
      None
    } catch {
      e => Some(e)
    }
    assert_true(refused is Some(_))
  }
}

///|
test "a target is shortened a segment at a time" {
  assert_eq(shorten("mirror::worker::sync", 20), "mirror::worker::sync")
  assert_eq(shorten("mirror::worker::sync", 15), "m::worker::sync")
  assert_eq(shorten("mirror::worker::sync", 5), "m::w::sync")
  assert_eq(shorten("com.example.app.Main", 12), "c.e.app.Main")
}

///|
/// The keys of a JSON object, in the order they were written.
fn top_keys(json : String) -> Array[String] {
  let out : Array[String] = []
  let chars = json.to_array()
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  let mut key = StringBuilder()
  let mut reading = false
  for i, c in chars {
    if in_string {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
        if reading {
          reading = false
          let mut next = i + 1
          while next < chars.length() && chars[next] == ' ' {
            next = next + 1
          }
          if next < chars.length() && chars[next] == ':' && depth == 1 {
            out.push(key.to_string())
          }
        }
      } else if reading {
        key.write_char(c)
      }
      continue
    }
    if c == '"' {
      in_string = true
      if depth == 1 {
        reading = true
        key = StringBuilder()
      }
      continue
    }
    if c == '{' || c == '[' {
      depth = depth + 1
    } else if c == '}' || c == ']' {
      depth = depth - 1
    }
  }
  out
}
