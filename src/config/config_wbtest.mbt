// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document with one of everything.
let sample_yaml : String =
  #|profile: slog
  #|filter: info, app=debug
  #|alarm:
  #|  tiers:
  #|    - [loki]
  #|    - [mail, console]
  #|  remind: 30m
  #|  fallback: panic
  #|slots:
  #|  console:
  #|    kind: stdio
  #|    stream: auto
  #|    level: warn
  #|    colour: false
  #|  file:
  #|    kind: file
  #|    path: /var/log/app.log
  #|    max_size: 32mb
  #|    every: 24h
  #|    keep: 7
  #|    max_age: 30d
  #|    max_total: 1GiB
  #|    compress: true
  #|    queue:
  #|      size: 4096
  #|      batch: 512
  #|      wait: 2s
  #|      full: block
  #|    retries: 2
  #|    probe: 10s

///|
/// The same configuration in JSON.
let sample_json : String =
  #|{
  #|  "profile": "slog",
  #|  "filter": "info, app=debug",
  #|  "alarm": {
  #|    "tiers": [["loki"], ["mail", "console"]],
  #|    "remind": "30m",
  #|    "fallback": "panic"
  #|  },
  #|  "slots": {
  #|    "console": {"kind": "stdio", "stream": "auto", "level": "warn", "colour": false},
  #|    "file": {
  #|      "kind": "file",
  #|      "path": "/var/log/app.log",
  #|      "max_size": "32mb",
  #|      "every": "24h",
  #|      "keep": 7,
  #|      "max_age": "30d",
  #|      "max_total": "1GiB",
  #|      "compress": true,
  #|      "queue": {"size": 4096, "batch": 512, "wait": "2s", "full": "block"},
  #|      "retries": 2,
  #|      "probe": "10s"
  #|    }
  #|  }
  #|}

///|
/// The same configuration in TOML.
let sample_toml : String =
  #|profile = "slog"
  #|filter = "info, app=debug"
  #|
  #|[alarm]
  #|tiers = [["loki"], ["mail", "console"]]
  #|remind = "30m"
  #|fallback = "panic"
  #|
  #|[slots.console]
  #|kind = "stdio"
  #|stream = "auto"
  #|level = "warn"
  #|colour = false
  #|
  #|[slots.file]
  #|kind = "file"
  #|path = "/var/log/app.log"
  #|max_size = "32mb"
  #|every = "24h"
  #|keep = 7
  #|max_age = "30d"
  #|max_total = "1GiB"
  #|compress = true
  #|retries = 2
  #|probe = "10s"
  #|
  #|[slots.file.queue]
  #|size = 4096
  #|batch = 512
  #|wait = "2s"
  #|full = "block"

///|
/// A name as a document writes it. The two characters that open one are kept
/// apart because the JavaScript backend reads them in a single literal as the
/// start of a template, and the code it emits does not parse.
fn ref_of(name : String) -> String {
  let out = StringBuilder()
  out.write_char('$')
  out.write_char('{')
  out.write_string(name)
  out.write_char('}')
  out.to_string()
}

///|
/// A lookup that answers one variable, so a document does not depend on the
/// environment the tests happen to run in.
fn env_with(name : String, value : String) -> (String) -> String? {
  fn(asked) { if asked == name { Some(value) } else { None } }
}

///|
test "a document says which profile, which filter, and what to write to" {
  let config = Config::parse(sample_yaml, lookup=env_with("UNUSED", "x"))
  assert_eq(config.profile().name(), "slog")
  assert_eq(config.filter(), "info, app=debug")
  assert_eq(config.slots().length(), 2)
  let console = match config.slot("console") {
    Some(slot) => slot
    None => fail("no console slot")
  }
  assert_eq(console.kind, "stdio")
  assert_eq(console.text("stream"), Some("auto"))
  assert_eq(console.filter, Some("warn"))
  assert_eq(console.colour, Some(false))
}

///|
test "sizes and spans are read in the units a deployment writes them in" {
  let config = Config::parse(sample_yaml, lookup=env_with("UNUSED", "x"))
  let file = match config.slot("file") {
    Some(slot) => slot
    None => fail("no file slot")
  }
  assert_eq(file.text("path"), Some("/var/log/app.log"))
  assert_eq(file.size("max_size"), Some(32_000_000L))
  assert_eq(file.size("max_total"), Some(1_073_741_824L))
  assert_eq(file.span("every"), Some(86_400_000_000_000L))
  assert_eq(file.span("max_age"), Some(2_592_000_000_000_000L))
  assert_eq(file.count("keep"), Some(7))
  assert_eq(file.flag("compress"), Some(true))
  assert_eq(file.retries, Some(2))
  assert_eq(file.probe, Some(10_000_000_000L))
}

///|
test "a queue keeps its defaults for what the document leaves out" {
  let config = Config::parse(sample_yaml, lookup=env_with("UNUSED", "x"))
  let file = match config.slot("file") {
    Some(slot) => slot
    None => fail("no file slot")
  }
  let queue = match file.queue {
    Some(queue) => queue
    None => fail("no queue")
  }
  assert_eq(queue.size, 4096)
  assert_eq(queue.batch, 512)
  assert_eq(queue.wait, 2_000_000_000L)
  assert_eq(queue.full, @moonlog.Full::Block)
}

///|
test "an alarm names its tiers and how long it waits before reminding" {
  let config = Config::parse(sample_yaml, lookup=env_with("UNUSED", "x"))
  let alarm = match config.alarm() {
    Some(alarm) => alarm
    None => fail("no alarm")
  }
  assert_eq(alarm.tiers.length(), 2)
  assert_eq(alarm.tiers[0], ["loki"])
  assert_eq(alarm.tiers[1], ["mail", "console"])
  assert_eq(alarm.remind, 1_800_000_000_000L)
  assert_eq(alarm.fallback, @moonlog.Fallback::Panic)
}

///|
test "the three formats read the same document into the same configuration" {
  let from_yaml = Config::parse(sample_yaml, lookup=env_with("UNUSED", "x"))
  let from_json = Config::parse(
    sample_json,
    format=Format::Json,
    lookup=env_with("UNUSED", "x"),
  )
  let from_toml = Config::parse(
    sample_toml,
    format=Format::Toml,
    lookup=env_with("UNUSED", "x"),
  )
  for config in [from_json, from_toml] {
    assert_eq(config.profile().name(), from_yaml.profile().name())
    assert_eq(config.filter(), from_yaml.filter())
    assert_eq(config.slots().length(), from_yaml.slots().length())
    let file = match config.slot("file") {
      Some(slot) => slot
      None => fail("no file slot")
    }
    assert_eq(file.text("path"), Some("/var/log/app.log"))
    assert_eq(file.size("max_size"), Some(32_000_000L))
    assert_eq(file.span("every"), Some(86_400_000_000_000L))
  }
}

///|
test "an unknown key is refused with the path it sits at" {
  let document =
    #|slots:
    #|  file:
    #|    kind: file
    #|    path: app.log
    #|    max_sise: 10mb
  let located = try {
    ignore(Config::parse(document))
    ""
  } catch {
    Refused(at~, ..) => at
  }
  assert_eq(located, "slots.file.max_sise")
}

///|
test "a key of the wrong shape is refused where it sits" {
  let document =
    #|slots:
    #|  file:
    #|    kind: file
    #|    path: app.log
    #|    keep: "seven"
  let answer = try {
    ignore(Config::parse(document))
    ""
  } catch {
    Refused(at~, got~, want~) => at + " | " + got + " | " + want
  }
  assert_eq(answer, "slots.file.keep | `seven` | a number")
}

///|
test "a slot without a kind, or of a kind nothing reads, is refused" {
  let unknown_document =
    #|slots:
    #|  a:
    #|    kind: syslog
  let unknown = try {
    ignore(Config::parse(unknown_document))
    ""
  } catch {
    Refused(at~, got~, ..) => at + " " + got
  }
  assert_eq(unknown, "slots.a.kind `syslog`")
  let bare_document =
    #|slots:
    #|  a:
    #|    path: app.log
  let none = try {
    ignore(Config::parse(bare_document))
    ""
  } catch {
    Refused(at~, got~, ..) => at + " " + got
  }
  assert_eq(none, "slots.a.kind nothing")
}

///|
test "a name the environment does not have is refused rather than left empty" {
  let document = (
    #|slots:
    #|  loki:
    #|    kind: loki
    #|    url: "URL_HERE"
  ).replace_all(old="URL_HERE", new=ref_of("LOKI_URL"))
  let answer = try {
    ignore(Config::parse(document, lookup=env_with("OTHER", "x")))
    ""
  } catch {
    Refused(at~, got~, ..) => at + " " + got
  }
  assert_eq(answer, "slots.loki.url " + ref_of("LOKI_URL"))
}

///|
test "a name the environment does have is put in its place, wherever it sits" {
  let document = (
      #|slots:
      #|  loki:
      #|    kind: loki
      #|    url: "http://host/URL_HERE"
      #|    labels:
      #|      job: "JOB_HERE"
    )
    .replace_all(old="URL_HERE", new=ref_of("TENANT"))
    .replace_all(old="JOB_HERE", new=ref_of("JOB"))
  let config = Config::parse(document, lookup=fn(name) {
    if name == "TENANT" {
      Some("acme")
    } else if name == "JOB" {
      Some("gateway")
    } else {
      None
    }
  })
  let loki = match config.slot("loki") {
    Some(slot) => slot
    None => fail("no loki slot")
  }
  assert_eq(loki.text("url"), Some("http://host/acme"))
  assert_eq(loki.pairs("labels"), Some([("job", "gateway")]))
}

///|
test "a configuration written back reads as the same configuration" {
  let config = Config::parse(sample_yaml, lookup=env_with("UNUSED", "x"))
  for format in [Format::Yaml, Format::Json, Format::Toml] {
    let written = config.dump(format~)
    let again = Config::parse(written, format~)
    assert_eq(again.filter(), config.filter())
    let file = match again.slot("file") {
      Some(slot) => slot
      None =>
        fail(
          "no file slot after a round trip through " + format.name().to_owned(),
        )
    }
    assert_eq(file.text("path"), Some("/var/log/app.log"))
    assert_eq(file.size("max_size"), Some(32_000_000L))
    assert_eq(file.span("max_age"), Some(2_592_000_000_000_000L))
    assert_eq(file.count("keep"), Some(7))
    assert_eq(file.flag("compress"), Some(true))
    assert_true(file.queue is Some(_))
  }
}

///|
test "the format of a file is taken from its name" {
  assert_eq(Format::of("conf/app.yaml").name(), "yaml")
  assert_eq(Format::of("app.json").name(), "json")
  assert_eq(Format::of("/etc/log.toml").name(), "toml")
  let answer = try {
    ignore(Format::of("app.conf"))
    ""
  } catch {
    Refused(got~, ..) => got
  }
  assert_eq(answer, "conf")
}

///|
test "a queue without a size is refused, because a queue that cannot fill is not one" {
  let document =
    #|slots:
    #|  file:
    #|    kind: file
    #|    path: app.log
    #|    queue:
    #|      batch: 10
  let answer = try {
    ignore(Config::parse(document))
    ""
  } catch {
    Refused(at~, ..) => at
  }
  assert_eq(answer, "slots.file.queue.size")
}

///|
/// A file of this run's own, under the temporary directory the system reports.
#cfg(target="native")
fn place(name : String) -> String {
  let base = match @env.get_env_var("TMPDIR") {
    Some(dir) =>
      if dir != "" {
        dir
      } else {
        match @env.get_env_var("TEMP") {
          Some(dir) => dir
          None => "."
        }
      }
    None => "."
  }
  let joiner = if base.contains("\\") { "\\" } else { "/" }
  base + joiner + "moonlog-config-" + name + "-" + @env.now().to_string()
}

///|
#cfg(target="native")
test "a watcher answers the new document when the file changes" {
  let path = place("watch") + ".yaml"
  let first =
    #|filter: info
    #|slots:
    #|  console:
    #|    kind: stdio
  match write_text(path, first) {
    Ok(_) => ()
    Err(why) => fail(why)
  }
  let watcher = Config::watch(path~)
  assert_eq(watcher.path(), path)
  match watcher.poll() {
    Ok(None) => ()
    Ok(Some(_)) => fail("the watcher answered a document that was not new")
    Err(why) => fail(why)
  }
  let second =
    #|filter: debug
    #|slots:
    #|  console:
    #|    kind: stdio
  match write_text(path, second) {
    Ok(_) => ()
    Err(why) => fail(why)
  }
  match watcher.poll() {
    Ok(Some(config)) => assert_eq(config.filter(), "debug")
    Ok(None) => fail("the watcher missed a new document")
    Err(why) => fail(why)
  }
  match write_text(path, "filter: [") {
    Ok(_) => ()
    Err(why) => fail(why)
  }
  match watcher.poll() {
    Ok(_) => fail("a broken document was accepted")
    Err(_) => ()
  }
}

///|
test "the published schema allows what the parser reads, and nothing else" {
  let schema = @moonschema.Schema::new(Config::schema())
  let good = @moonyaml.loads(
    sample_yaml,
    flavor=@moonyaml.strict,
    schema=@moonyaml.core,
  )
  assert_true(schema.valid(good))
  let typo_document =
    #|slots:
    #|  app:
    #|    kind: file
    #|    path: app.log
    #|    max_sise: 10mb
  let typo = @moonyaml.loads(
    typo_document,
    flavor=@moonyaml.strict,
    schema=@moonyaml.core,
  )
  assert_false(schema.valid(typo))
  let unknown_document =
    #|slots:
    #|  app:
    #|    kind: syslog
  let unknown = @moonyaml.loads(
    unknown_document,
    flavor=@moonyaml.strict,
    schema=@moonyaml.core,
  )
  assert_false(schema.valid(unknown))
  // A file slot without a path is refused by both halves as well.
  let pathless_document =
    #|slots:
    #|  app:
    #|    kind: file
  let pathless = @moonyaml.loads(
    pathless_document,
    flavor=@moonyaml.strict,
    schema=@moonyaml.core,
  )
  assert_false(schema.valid(pathless))
}
