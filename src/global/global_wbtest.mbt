// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document with two slots that write nowhere near a terminal.
fn quiet_document() -> @config.Config raise {
  let document =
    #|filter: debug
    #|slots:
    #|  kept:
    #|    kind: memory
    #|    size: 16
    #|  dropped:
    #|    kind: discard
  @config.Config::parse(document)
}

///|
test "SERLOG_FORMAT names a layout, and says so when it names none" {
  let logfmt = layout_of("logfmt").render(
    @moonlog.Record::of(@moonlog.info, "a", "m"),
    @moonlog.Scene::new(),
  )
  assert_true(logfmt.contains("msg="))
  let line = layout_of("pattern:{msg}").render(
    @moonlog.Record::of(@moonlog.info, "a", "only this"),
    @moonlog.Scene::new(),
  )
  assert_eq(line, "only this")
  assert_true(
    layout_of("json")
    .render(@moonlog.Record::of(@moonlog.info, "a", "m"), @moonlog.Scene::new())
    .has_prefix("{"),
  )
  assert_true(
    layout_of("json:pino")
    .render(@moonlog.Record::of(@moonlog.info, "a", "m"), @moonlog.Scene::new())
    .contains("\"level\""),
  )
  let refused = try {
    ignore(
      layout_of("nonsense").render(
        @moonlog.Record::of(@moonlog.info, "a", "m"),
        @moonlog.Scene::new(),
      ),
    )
    ""
  } catch {
    @config.Refused(at~, got~, ..) => at + " " + got
  }
  assert_eq(refused, "SERLOG_FORMAT `nonsense`")
}

///|
test "a document decides which slots there are" {
  start(config=quiet_document())
  let status = hub().status()
  assert_eq(status.length(), 2)
  assert_eq(status[0].name, "kept")
  assert_eq(status[0].kind, "memory")
  assert_eq(status[1].name, "dropped")
  assert_eq(status[1].kind, "discard")
  shutdown()
}

///|
test "the filter in the document decides what gets through" {
  start(config=quiet_document())
  let log = logger("gateway")
  assert_true(log.enabled(@moonlog.debug))
  assert_false(log.enabled(@moonlog.trace))
  shutdown()
}

///|
test "a filter handed in overrides the document" {
  start(config=quiet_document(), filter="warn")
  let log = logger("gateway")
  assert_false(log.enabled(@moonlog.info))
  assert_true(log.enabled(@moonlog.error))
  shutdown()
}

///|
test "nothing at all is a console at the profile's own stream" {
  shutdown()
  start()
  let status = hub().status()
  assert_eq(status.length(), 1)
  assert_eq(status[0].name, "console")
  assert_eq(status[0].kind, "stdio")
  shutdown()
}

///|
test "a filter that will not parse is refused where it came from" {
  let answer = try {
    start(filter="app=oops")
    ""
  } catch {
    @config.Refused(at~, got~, ..) => at + " " + got
  }
  assert_true(answer.has_prefix("filter `"))
  shutdown()
}

///|
test "the level can be changed while the process runs" {
  start(config=quiet_document())
  let log = logger("gateway")
  assert_true(log.enabled(@moonlog.debug))
  set_level(@moonlog.error)
  assert_false(log.enabled(@moonlog.warn))
  assert_true(log.enabled(@moonlog.error))
  shutdown()
}

///|
test "a logger asked for before anything else starts a console" {
  shutdown()
  let log = logger("early")
  assert_eq(hub().status().length(), 1)
  assert_true(log.target() == "early")
  shutdown()
}

///|
test "a slot kind nothing reads is refused while the document is read" {
  let document =
    #|slots:
    #|  odd:
    #|    kind: syslog
  let answer = try {
    ignore(@config.Config::parse(document))
    ""
  } catch {
    @config.Refused(at~, got~, ..) => at + " " + got
  }
  assert_eq(answer, "slots.odd.kind `syslog`")
}

///|
test "a file slot writes where the document says, and flush leaves it there" {
  let base = match @env.get_env_var("TEMP") {
    Some(dir) => if dir == "" { "." } else { dir }
    None => "."
  }
  let joiner = if base.contains("\\") { "\\" } else { "/" }
  let path = base + joiner + "moonlog-global-" + @env.now().to_string() + ".log"
  let document =
    #|filter: info
    #|slots:
    #|  file:
    #|    kind: file
    #|    path: PATH
  let config = @config.Config::parse(document.replace_all(old="PATH", new=path))
  start(config~)
  logger("gateway").info("written through the process hub")
  flush()
  assert_eq(hub().status()[0].health, @moonlog.Health::Up)
  shutdown()
}
