// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The configuration examples the shared specification publishes, generated
/// from `scripts/serlog-examples/` by `scripts/gen_examples.py`: one test per
/// document, each asserting what the document says, key by key.
///
/// A document is a deployment's, so it is read with a lookup of its own: a
/// test that depended on the environment would pass or fail by whose machine
/// ran it.
fn example_env(name : String) -> String? {
  if name == "SMTP_PASS" {
    Some("s3cret")
  } else {
    None
  }
}

///|
/// A document read, or a test failure that says where the reader stopped.
fn example_read(document : String) -> Config raise {
  Config::parse(document, lookup=example_env) catch {
    error => fail("the document was refused at " + error.to_text())
  }
}

///|
/// The slot a document describes under `name`, or a failure naming the ones it
/// does describe.
fn example_slot(config : Config, name : String) -> Slot raise {
  match config.slot(name) {
    Some(slot) => slot
    None => {
      let names : Array[String] = []
      for slot in config.slots() {
        names.push(slot.name)
      }
      fail("no slot called " + name + ", only " + names.join(", "))
    }
  }
}

///|
/// From the specification's config page: one of everything.
test "examples: the config page's mirror deployment" {
  let document =
    #|app: mirror
    #|env: prod
    #|compat: serlog
    #|filter: info,hustsync=debug
    #|levels: { notice: { value: 35, colour: blue } }
    #|process: [{ fields: { region: cn } }]
    #|redact: [pass, token]
    #|watch: 30s
    #|sinks:
    #|  - kind: console
    #|  - { kind: file, name: app, path: /var/log/app.log, max_size: 64MiB, keep: 7, gzip: true }
    #|  - { kind: loki, url: "http://alloy:3100/loki/api/v1/push", on_fail: ops }
    #|  - { kind: mail, name: oncall, alarm_only: true, host: smtp.example.org, user: bot@example.org, pass: "${SMTP_PASS}", to: [ops@example.org] }
    #|alarms:
    #|  ops: { tiers: [[oncall], [stderr]], on_fail: panic, remind: 30m }
  let config = example_read(document)
  assert_eq(config.app, "mirror")
  assert_eq(config.env, "prod")
  assert_eq(config.instance, "")
  assert_eq(config.profile.name(), "serlog")
  assert_eq(config.filter, "info,hustsync=debug")
  assert_eq(config.levels.length(), 1)
  assert_eq(config.levels[0].name, "notice")
  assert_eq(config.levels[0].value, 35)
  assert_true(config.levels[0].colour == @moonlog.Colour::Blue)
  assert_eq(config.chain.length(), 2)
  assert_eq(config.alarms.length(), 1)
  assert_eq(config.alarms[0].0, "ops")
  assert_eq(config.alarms[0].1.tiers, [["oncall"], ["stderr"]])
  assert_eq(config.alarms[0].1.remind, 1_800_000_000_000L)
  assert_true(config.alarms[0].1.fallback == @moonlog.Fallback::Panic)
  assert_eq(config.watch, Some(30_000_000_000L))
  assert_eq(config.slots().length(), 4)
  let slot = example_slot(config, "console-1")
  assert_eq(slot.kind, "console")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  let slot = example_slot(config, "app")
  assert_eq(slot.kind, "file")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  assert_eq(slot.text("path"), Some("/var/log/app.log"))
  assert_eq(slot.size("max_size"), Some(67108864L))
  assert_eq(slot.count("keep"), Some(7))
  assert_eq(slot.flag("compress"), Some(true))
  let slot = example_slot(config, "loki-1")
  assert_eq(slot.kind, "loki")
  assert_eq(slot.alarm_only, false)
  assert_eq(slot.on_fail, Some("ops"))
  assert_true(slot.layout is None)
  assert_eq(slot.text("url"), Some("http://alloy:3100/loki/api/v1/push"))
  let slot = example_slot(config, "oncall")
  assert_eq(slot.kind, "mail")
  assert_eq(slot.alarm_only, true)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  assert_eq(slot.text("host"), Some("smtp.example.org"))
  assert_eq(slot.text("username"), Some("bot@example.org"))
  assert_eq(slot.text("password"), Some("s3cret"))
  assert_eq(slot.texts("to"), Some(["ops@example.org"]))
}

///|
/// From the specification's start page: a console, a file and a shipper.
test "examples: the start page's first deployment" {
  let document =
    #|app: mirror
    #|filter: info,hustsync=debug
    #|sinks:
    #|  - kind: console
    #|  - { kind: file, name: app, path: logs/app.log, rotate: day, keep: 7, gzip: true }
    #|  - { kind: loki, url: "http://alloy:3100/loki/api/v1/push", labels: { team: mirrors } }
  let config = example_read(document)
  assert_eq(config.app, "mirror")
  assert_eq(config.env, "")
  assert_eq(config.profile.name(), "serlog")
  assert_eq(config.filter, "info,hustsync=debug")
  assert_eq(config.chain.length(), 0)
  assert_eq(config.alarms.length(), 0)
  assert_true(config.watch is None)
  assert_eq(config.slots().length(), 3)
  let slot = example_slot(config, "console-1")
  assert_eq(slot.kind, "console")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  let slot = example_slot(config, "app")
  assert_eq(slot.kind, "file")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  assert_eq(slot.text("path"), Some("logs/app.log"))
  assert_eq(slot.span("every"), Some(86400000000000L))
  assert_eq(slot.count("keep"), Some(7))
  assert_eq(slot.flag("compress"), Some(true))
  let slot = example_slot(config, "loki-1")
  assert_eq(slot.kind, "loki")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  assert_eq(slot.text("url"), Some("http://alloy:3100/loki/api/v1/push"))
  assert_eq(slot.pairs("labels"), Some([("team", "mirrors")]))
}

///|
/// From the specification's page on failures: an alarm and its route.
test "examples: the failures page's alarm" {
  let document =
    #|sinks:
    #|  - { kind: loki, url: "http://alloy:3100/loki/api/v1/push", on_fail: ops }
    #|  - { kind: mail, name: oncall, alarm_only: true, host: smtp.example.org, to: [ops@example.org] }
    #|alarms:
    #|  ops: { tiers: [[oncall], [stderr]], remind: 30m }
  let config = example_read(document)
  assert_eq(config.app, "")
  assert_eq(config.alarms.length(), 1)
  assert_eq(config.alarms[0].0, "ops")
  assert_eq(config.alarms[0].1.tiers, [["oncall"], ["stderr"]])
  assert_true(config.alarms[0].1.fallback == @moonlog.Fallback::Ignore)
  assert_true(config.alarm is None)
  assert_eq(config.slots().length(), 2)
  let slot = example_slot(config, "loki-1")
  assert_eq(slot.kind, "loki")
  assert_eq(slot.alarm_only, false)
  assert_eq(slot.on_fail, Some("ops"))
  assert_true(slot.layout is None)
  assert_eq(slot.text("url"), Some("http://alloy:3100/loki/api/v1/push"))
  let slot = example_slot(config, "oncall")
  assert_eq(slot.kind, "mail")
  assert_eq(slot.alarm_only, true)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  assert_eq(slot.text("host"), Some("smtp.example.org"))
  assert_eq(slot.texts("to"), Some(["ops@example.org"]))
}

///|
/// From the specification's README, and the five language READMEs under it.
test "examples: the README's deployment" {
  let document =
    #|app: mirror
    #|filter: info,hustsync=debug
    #|redact: [pass]
    #|sinks:
    #|  - kind: console
    #|  - { kind: file, name: app, path: /var/log/app.log, max_size: 64MiB, keep: 7, gzip: true }
    #|  - { kind: loki, url: "http://alloy:3100/loki/api/v1/push", on_fail: ops }
    #|alarms:
    #|  ops: { tiers: [[stderr]], remind: 30m }
    #|watch: 30s
  let config = example_read(document)
  assert_eq(config.app, "mirror")
  assert_eq(config.filter, "info,hustsync=debug")
  assert_eq(config.chain.length(), 1)
  assert_eq(config.watch, Some(30_000_000_000L))
  assert_eq(config.alarms[0].1.tiers, [["stderr"]])
  assert_eq(config.slots().length(), 3)
  let slot = example_slot(config, "console-1")
  assert_eq(slot.kind, "console")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  let slot = example_slot(config, "app")
  assert_eq(slot.kind, "file")
  assert_eq(slot.alarm_only, false)
  assert_true(slot.on_fail is None)
  assert_true(slot.layout is None)
  assert_eq(slot.text("path"), Some("/var/log/app.log"))
  assert_eq(slot.size("max_size"), Some(67108864L))
  assert_eq(slot.count("keep"), Some(7))
  assert_eq(slot.flag("compress"), Some(true))
  let slot = example_slot(config, "loki-1")
  assert_eq(slot.kind, "loki")
  assert_eq(slot.alarm_only, false)
  assert_eq(slot.on_fail, Some("ops"))
  assert_true(slot.layout is None)
  assert_eq(slot.text("url"), Some("http://alloy:3100/loki/api/v1/push"))
}

///|
/// From the specification's Rust example, which registers a `phone` kind.
test "examples: the Rust example's own sink kind" {
  let document =
    #|app: mirror
    #|sinks:
    #|  - kind: console
    #|    pattern: "{level:<5} {msg}{fields}"
    #|  - kind: phone
    #|    name: oncall
    #|    phone: 13800138000
    #|    level: warn
    #|    pattern: "{level} {msg}"
  let refused = try {
    ignore(Config::parse(document, lookup=example_env))
    None
  } catch {
    Refused(at~, ..) => Some(at)
  }
  assert_eq(refused, Some("sinks.1.kind"))
}

///|
/// The same document with the kind brought along, which is all it took.
test "examples: a kind of the program's own reads its keys through the slot" {
  let document =
    #|app: mirror
    #|sinks:
    #|  - kind: console
    #|    pattern: "{level:<5} {msg}{fields}"
    #|  - kind: phone
    #|    name: oncall
    #|    phone: 13800138000
    #|    level: warn
    #|    pattern: "{level} {msg}"
  let dialled = Ref("")
  let phone = Kind::new("phone", keys=["phone"], slot => {
    dialled.val = match slot.count("phone") {
      Some(n) => n.to_string()
      None => slot.text("phone").unwrap_or("")
    }
    @moonlog.Discard::new()
  })
  let config = Config::parse(document, lookup=example_env, kinds=[phone])
  let slot = config.slots()[1]
  assert_eq(slot.kind, "phone")
  assert_eq(slot.name, "oncall")
  assert_true(config.build(slot) is Some(_))
  assert_true(dialled.val.length() > 0)
  assert_true(config.build(config.slots()[0]) is None)
}

///|
test "kinds: a key the kind does not read is refused, and a built-in name cannot be taken" {
  let document =
    #|sinks:
    #|  - kind: phone
    #|    name: oncall
    #|    pager: 1
  let phone = Kind::new("phone", keys=["phone"], _ => @moonlog.Discard::new())
  let at = (text : String, kinds : Array[Kind]) => {
    try {
      ignore(Config::parse(text, lookup=example_env, kinds~))
      None
    } catch {
      Refused(at~, ..) => Some(at)
    }
  }
  assert_eq(at(document, [phone]), Some("sinks.0.pager"))
  let taken = Kind::new("file", _ => @moonlog.Discard::new())
  assert_eq(at("app: a\n", [taken]), Some("kinds"))
  assert_eq(at("app: a\n", [phone, phone]), Some("kinds"))
}

///|
/// The config page's document with `max_size` written `max_sise`.
test "examples: a misspelt setting in the config page's document" {
  let document =
    #|app: mirror
    #|env: prod
    #|compat: serlog
    #|filter: info,hustsync=debug
    #|levels: { notice: { value: 35, colour: blue } }
    #|process: [{ fields: { region: cn } }]
    #|redact: [pass, token]
    #|watch: 30s
    #|sinks:
    #|  - kind: console
    #|  - { kind: file, name: app, path: /var/log/app.log, max_sise: 64MiB, keep: 7, gzip: true }
    #|  - { kind: loki, url: "http://alloy:3100/loki/api/v1/push", on_fail: ops }
    #|  - { kind: mail, name: oncall, alarm_only: true, host: smtp.example.org, user: bot@example.org, pass: "${SMTP_PASS}", to: [ops@example.org] }
    #|alarms:
    #|  ops: { tiers: [[oncall], [stderr]], on_fail: panic, remind: 30m }
  let refused = try {
    ignore(Config::parse(document, lookup=example_env))
    None
  } catch {
    Refused(at~, ..) => Some(at)
  }
  assert_eq(refused, Some("sinks.1.max_sise"))
}

///|
/// The config page's document, written out in each format and read again.
test "examples: a document written back reads the same" {
  let document =
    #|app: mirror
    #|env: prod
    #|compat: serlog
    #|filter: info,hustsync=debug
    #|levels: { notice: { value: 35, colour: blue } }
    #|process: [{ fields: { region: cn } }]
    #|redact: [pass, token]
    #|watch: 30s
    #|sinks:
    #|  - kind: console
    #|  - { kind: file, name: app, path: /var/log/app.log, max_size: 64MiB, keep: 7, gzip: true }
    #|  - { kind: loki, url: "http://alloy:3100/loki/api/v1/push", on_fail: ops }
    #|  - { kind: mail, name: oncall, alarm_only: true, host: smtp.example.org, user: bot@example.org, pass: "${SMTP_PASS}", to: [ops@example.org] }
    #|alarms:
    #|  ops: { tiers: [[oncall], [stderr]], on_fail: panic, remind: 30m }
  let config = example_read(document)
  for format in [Format::Yaml, Format::Json, Format::Toml] {
    let again = Config::parse(config.dump(format~), format~)
    assert_eq(again.app(), "mirror")
    assert_eq(again.env(), "prod")
    assert_eq(again.filter(), "info,hustsync=debug")
    assert_eq(again.profile().name(), "serlog")
    assert_eq(again.levels().length(), 1)
    assert_eq(again.chain().length(), 2)
    assert_eq(again.process().length(), 2)
    assert_eq(again.alarms().length(), 1)
    assert_eq(again.watch_span(), Some(30_000_000_000L))
    assert_eq(again.slots().length(), 4)
    let file = example_slot(again, "app")
    assert_eq(file.text("path"), Some("/var/log/app.log"))
    assert_eq(file.size("max_size"), Some(67_108_864L))
    assert_eq(file.flag("compress"), Some(true))
    let loki = example_slot(again, "loki-1")
    assert_eq(loki.on_fail, Some("ops"))
    let mail = example_slot(again, "oncall")
    assert_eq(mail.alarm_only, true)
  }
}
