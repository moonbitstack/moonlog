// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a record keeps fields in order and updates an existing key in place" {
  let base = @moonlog.Record::of(@moonlog.info, "app", "hi")
  let first = base
    .set("a", @moonlog.Value::of_int(1))
    .set("b", @moonlog.Value::of_int(2))
  assert_eq(first.fields.map(fn(p) { p.0 }), ["a", "b"])
  // Setting an existing key replaces it where it stands, not at the end.
  let second = first.set("a", @moonlog.Value::of_int(9))
  assert_eq(second.fields.map(fn(p) { p.0 }), ["a", "b"])
  assert_eq(second.field("a").map(fn(v) { v.to_text() }), Some("9"))
  assert_eq(second.field("b").map(fn(v) { v.to_text() }), Some("2"))
  // A new name appends after the bound ones.
  let third = second.set("c", @moonlog.Value::of_str("x"))
  assert_eq(third.fields.map(fn(p) { p.0 }), ["a", "b", "c"])
}

///|
test "sets applies pairs in order and unset drops one without reordering" {
  let r = @moonlog.Record::of(@moonlog.info, "app", "hi").sets([
    ("x", @moonlog.Value::of_int(1)),
    ("y", @moonlog.Value::of_int(2)),
    ("x", @moonlog.Value::of_int(3)),
  ])
  assert_eq(r.field("x").map(fn(v) { v.to_text() }), Some("3"))
  assert_eq(r.field("y").map(fn(v) { v.to_text() }), Some("2"))
  let kept = r.unset("x")
  assert_eq(kept.has("x"), false)
  assert_eq(kept.has("y"), true)
  assert_eq(kept.fields.map(fn(p) { p.0 }), ["y"])
}

///|
test "a copy shares no arrays with its source" {
  let r = @moonlog.Record::of(@moonlog.info, "app", "hi").set(
    "a",
    @moonlog.Value::of_int(1),
  )
  let c = r.copy()
  let changed = c.set("a", @moonlog.Value::of_int(2)).say("bye")
  assert_eq(r.field("a").map(fn(v) { v.to_text() }), Some("1"))
  assert_eq(r.msg, "hi")
  assert_eq(changed.field("a").map(fn(v) { v.to_text() }), Some("2"))
  assert_eq(changed.msg, "bye")
}

///|
test "a record carries level, time, seq, caller, thread and tags" {
  let r = @moonlog.Record::of(@moonlog.warn, "app", "hi")
    .at(@moonlog.error)
    .stamped(123L)
    .numbered(7L)
    .located("main.mbt", line=42)
    .on("worker")
    .tag("slow")
    .tag("slow")
  assert_eq(r.level.name(), "error")
  assert_eq(r.time, 123L)
  assert_eq(r.seq, 7L)
  assert_eq(r.caller.file, Some("main.mbt"))
  assert_eq(r.caller.line, Some(42))
  assert_eq(r.thread, Some("worker"))
  assert_eq(r.tagged("slow"), true)
  assert_eq(r.tagged("fast"), false)
  assert_eq(r.tags, ["slow", "slow"])
}

///|
test "an identity names nobody by default and only what it is told" {
  let empty = @moonlog.Identity::new()
  assert_eq(empty.app, "")
  assert_eq(empty.pid, 0)
  let given = @moonlog.Identity::of(app="svc", host="h1", pid=9)
  assert_eq(given.app, "svc")
  assert_eq(given.host, "h1")
  assert_eq(given.pid, 9)
  assert_eq(given.env, "")
}

///|
test "a logger skips work the hub would drop" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::at(@moonlog.warn))
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  let log = hub.logger("app")
  assert_eq(log.enabled(@moonlog.info), false)
  assert_eq(log.enabled(@moonlog.warn), true)
  log.info("quiet")
  log.warn("loud")
  assert_eq(sink.lines().length(), 1)
  assert_eq(sink.lines()[0].contains("loud"), true)
}

///|
test "a logger's bound fields do not leak into the logger it copied from" {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(filter=@moonlog.Filter::at(@moonlog.trace))
  ignore(hub.add(@moonlog.Slot::new(sink, name="mem")))
  let base = hub.logger("app")
  let bound = base.bound("k", @moonlog.Value::of_int(1))
  base.info("from base")
  bound.info("from bound")
  let records = sink.records()
  assert_eq(records[0].has("k"), false)
  assert_eq(records[1].field("k").map(fn(v) { v.to_text() }), Some("1"))
  let child = base.under("app::sub")
  assert_eq(child.target(), "app::sub")
  assert_eq(child.target() == base.target(), false)
}
