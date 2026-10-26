///|
test "a hub refuses `*` and a second slot of the same name" {
  let hub = @moonlog.Hub::new()
  assert_eq(
    hub.add(@moonlog.Slot::new(@moonlog.Memory::new(), name="mem")),
    "mem",
  )
  let star = try {
    ignore(hub.add(@moonlog.Slot::new(@moonlog.Memory::new(), name="*")))
    false
  } catch {
    @moonlog.Refused(got~, ..) => got == "*"
  }
  assert_eq(star, true)
  let twice = try {
    ignore(hub.add(@moonlog.Slot::new(@moonlog.Memory::new(), name="mem")))
    false
  } catch {
    @moonlog.Refused(got~, ..) => got == "mem"
  }
  assert_eq(twice, true)
}

///|
test "removing a slot writes what its queue holds first" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new()
  ignore(
    hub.add(
      @moonlog.Slot::new(sink, name="mem").queue(
        @moonlog.Queue::new(size=8).batch(100),
      ),
    ),
  )
  ignore(hub.add(@moonlog.Slot::new(@moonlog.Discard::new(), name="void")))
  hub.logger("app").info("queued")
  assert_eq(sink.lines().length(), 0)
  assert_eq(hub.remove("mem"), true)
  assert_eq(sink.lines().length(), 1)
  assert_eq(hub.remove("mem"), false)
  assert_eq(hub.slots().map(s => s.name()), ["void"])
}

///|
test "the hub answers what the alarm walk asks of it" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new()
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  ignore(
    hub.add(
      @moonlog.Slot::new(@moonlog.Discard::new(), name="pager").alarm_only(),
    ),
  )
  assert_eq(hub.logs(), ["mem"])
  assert_eq(hub.resting("mem"), false)
  assert_eq(hub.resting("nobody"), true)
  let record = @moonlog.Record::of(@moonlog.error, "alarm", "sink down")
  assert_eq(hub.deliver("mem", record) is Ok(_), true)
  assert_eq(sink.lines().length(), 1)
  assert_eq(hub.deliver("nobody", record), Err("no sink called `nobody`"))
}

///|
test "the hub's settings read back and change at run time" {
  let hub = @moonlog.Hub::new(
    identity=@moonlog.Identity::of(app="demo"),
    profile=@moonlog.Profile::Python,
  )
  assert_eq(hub.identity().app, "demo")
  assert_eq(hub.profile().name(), "python")
  assert_eq(hub.enabled(@moonlog.info), false)
  hub.set_level(@moonlog.debug)
  assert_eq(hub.enabled(@moonlog.debug), true)
  assert_eq(hub.filter().allows(@moonlog.trace, "any"), false)
}

///|
test "health names itself" {
  assert_eq(@moonlog.Up.name(), "up")
  assert_eq(@moonlog.Down.name(), "down")
  assert_eq(@moonlog.Probing.name(), "probing")
}

///|
test "a logger binds fields, narrows its target and writes every level" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::at(@moonlog.trace))
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  let log = hub
    .logger("app")
    .bound("req", @moonlog.Value::of_int(1))
    .bound("req", @moonlog.Value::of_int(2))
  assert_eq(log.target(), "app")
  let child = log.under("app::db")
  assert_eq(child.target(), "app::db")
  child.trace("t")
  child.fatal("f")
  let records = sink.records()
  assert_eq(records.map(r => r.level.name()), ["trace", "fatal"])
  assert_eq(records[0].field("req").map(v => v.to_text()), Some("2"))
}
