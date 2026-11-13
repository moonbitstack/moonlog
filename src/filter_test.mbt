// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a filter's lowest level spans the base and every rule" {
  assert_eq(@moonlog.Filter::off().lowest() is None, true)
  assert_eq(
    @moonlog.Filter::at(@moonlog.debug).lowest().map(fn(l) { l.name() }),
    Some("debug"),
  )
  let f = @moonlog.Filter::parse("info,app=debug,app::net=off")
  // `debug` is the quietest level any target allows.
  assert_eq(f.lowest().map(fn(l) { l.name() }), Some("debug"))
}

///|
test "a target-specific rule beats the base and off silences" {
  let f = @moonlog.Filter::parse("info,app=debug,app::net=off")
  assert_eq(f.allows(@moonlog.info, "elsewhere"), true)
  assert_eq(f.allows(@moonlog.debug, "app"), true)
  assert_eq(f.allows(@moonlog.info, "app::net"), false)
  assert_eq(f.allows(@moonlog.debug, "app::net::tcp"), false)
}

///|
test "a filter reads back as the spec it parsed" {
  let f = @moonlog.Filter::parse("warn,web:*=error,app=debug/app")
  assert_eq(f.to_text(), "warn,app=debug,web:*=error/app")
  assert_eq(f.has_pattern(), true)
}

///|
test "a filter that never matches a message admits nothing" {
  let f = @moonlog.Filter::parse("info/needle")
  assert_eq(f.admits(@moonlog.info, "app", "has no match here"), false)
  assert_eq(f.admits(@moonlog.info, "app", "a needle in the hay"), true)
}
