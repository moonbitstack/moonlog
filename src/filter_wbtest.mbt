// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The filter vectors of the shared specification: the first directive that
/// covers a target decides, literal targets beat wildcards, and a target
/// matches everything under it but not a name that merely starts the same way.
test "filters pick the most specific directive" {
  let spec = "warn, app=debug, app::db=trace, app::net=off, noisy"
  let filter = Filter::parse(spec)
  assert_true(filter.allows(warn, "other"))
  assert_false(filter.allows(info, "other"))
  assert_true(filter.allows(debug, "app"))
  assert_true(filter.allows(debug, "app::sync"))
  assert_false(filter.allows(trace, "app::sync"))
  assert_true(filter.allows(trace, "app::db::pool"))
  assert_false(filter.allows(error, "app::net"))
  assert_true(filter.allows(trace, "noisy::x"))
  assert_false(filter.allows(debug, "apparent"))
}

///|
test "an empty spec lets errors through and off lets nothing" {
  assert_true(Filter::parse("").allows(error, "x"))
  assert_true(Filter::parse("").allows(fatal, "x"))
  assert_false(Filter::parse("").allows(warn, "x"))
  assert_false(Filter::parse("off").allows(fatal, "any"))
  assert_true(Filter::parse("off").lowest() is None)
}

///|
test "targets split at dots as well as colons" {
  let filter = Filter::parse("info,com.acme=debug,com.acme.db=off")
  assert_true(filter.allows(debug, "com.acme.web"))
  assert_true(filter.allows(info, "org.x"))
  assert_false(filter.allows(debug, "org.x"))
  assert_false(filter.allows(error, "com.acme.db.pool"))
  assert_false(filter.allows(debug, "com.acmex"))
}

///|
test "a wildcard covers a target and only what is under it" {
  let filter = Filter::parse("warn,web:*=error,app=debug")
  assert_true(filter.allows(error, "web:api"))
  assert_false(filter.allows(warn, "web:api"))
  assert_true(filter.allows(debug, "app::x"))
  assert_true(filter.allows(warn, "other"))
  assert_false(filter.allows(info, "other"))
}

///|
test "a bare number is a level by value" {
  let filter = Filter::parse("35")
  assert_true(filter.allows(warn, "x"))
  assert_false(filter.allows(info, "x"))
  let tight = Filter::parse("info,app=fatal")
  assert_true(tight.allows(fatal, "app"))
  assert_false(tight.allows(error, "app"))
}

///|
test "a slash adds a regular expression the message must match" {
  let filter = Filter::parse("info/sync(ed)?")
  assert_true(filter.admits(info, "x", "synced 3 files"))
  assert_false(filter.admits(info, "x", "idle"))
  assert_true(filter.has_pattern())
  assert_eq(filter.to_text(), "info/sync(ed)?")
  assert_eq(Filter::parse("warn, app=debug").to_text(), "warn,app=debug")
  assert_eq(Filter::parse("noisy").to_text(), "off,noisy")
}

///|
test "a level by name, number or another logger's word" {
  assert_true(Level::parse("WaRn") == warn)
  assert_true(Level::parse("warning") == warn)
  assert_true(Level::parse("critical") == fatal)
  assert_eq(Level::parse("35").value, 35)
  assert_true(trace < info && info < fatal)
  assert_eq(warn.label(Profile::Python), "WARNING")
  assert_eq(trace.label(Profile::Slog), "DEBUG-4")
  assert_eq(fatal.label(Profile::Serlog), "FATAL")
}

///|
test "a refusal says where and what" {
  let refused = try {
    let _ = Filter::parse("app=loud")
    None
  } catch {
    e => Some(e)
  }
  guard refused is Some(Refused(at~, got~, want~)) else {
    fail("a level nobody knows is a refusal")
  }
  assert_eq(got, "app=loud")
  assert_true(want.contains(("level" : StringView)))
  assert_eq(at, 0)
}
