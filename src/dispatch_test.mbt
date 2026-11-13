// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the global filter drops what it does not admit" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::at(@moonlog.warn))
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  hub.logger("app").info("too quiet")
  hub.logger("app").warn("loud enough")
  assert_eq(sink.lines().length(), 1)
}

///|
test "a message filter only admits lines that match" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::parse("info/sail"))
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  hub.logger("app").info("set sail now")
  hub.logger("app").info("stay in port")
  assert_eq(sink.lines().length(), 1)
  assert_eq(sink.lines()[0].contains("sail"), true)
}

///|
test "a slot's own filter narrows what only that slot receives" {
  let kept = @moonlog.Memory::new()
  let dropped = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::at(@moonlog.trace))
  ignore(
    hub.add(
      @moonlog.Slot::new(kept, name="keep").filter(
        @moonlog.Filter::parse("debug"),
      ),
    ),
  )
  ignore(hub.add(@moonlog.Slot::new(dropped, name="drop")))
  hub.logger("app").trace("lowest")
  hub.logger("app").debug("low")
  assert_eq(kept.lines().length(), 1)
  assert_eq(dropped.lines().length(), 2)
}

///|
test "an alarm-only slot takes no normal line" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::at(@moonlog.trace))
  ignore(hub.add(@moonlog.Slot::new(sink, name="pager").alarm_only()))
  hub.logger("app").fatal("down")
  assert_eq(sink.lines().length(), 0)
}

///|
test "a hub filters by target through its slots" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(
    filter=@moonlog.Filter::parse("info,app::net=off"),
  )
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  hub.logger("app").info("kept")
  hub.logger("app::net").info("blocked")
  hub.logger("app::net::tcp").info("blocked too")
  assert_eq(sink.lines().length(), 1)
}
