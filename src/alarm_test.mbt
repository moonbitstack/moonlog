// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A desk the test controls: it remembers what was delivered, and which sinks
/// are down or resting. Arrays are shared by reference, so the deliveries the
/// `Desk` makes inside the alarm walk reach the test that built it.
struct TestDesk {
  routes : Array[String]
  delivered : Array[String]
  failing : Array[String]
  resting : Array[String]
}

///|
fn TestDesk::new(
  routes~ : Array[String] = [],
  failing~ : Array[String] = [],
  resting~ : Array[String] = [],
) -> TestDesk {
  { routes, failing, resting, delivered: [], }
}

///|
pub impl @moonlog.Desk for TestDesk with fn logs(self) -> Array[String] {
  self.routes.copy()
}

///|
pub impl @moonlog.Desk for TestDesk with fn resting(self, name : String) -> Bool {
  self.resting.contains(name)
}

///|
pub impl @moonlog.Desk for TestDesk with fn deliver(
  self,
  name : String,
  _record : @moonlog.Record,
) -> Result[Unit, String] {
  if self.failing.contains(name) {
    Err("down")
  } else {
    self.delivered.push(name)
    Ok(())
  }
}

///|
pub extend TestDesk with @moonlog.Desk::{logs, resting, deliver}

///|
test "an alarm skips the failing sink and stops at the first success" {
  let desk = TestDesk::new(failing=["a"])
  let alarm = @moonlog.Tiers::from([["a"], ["b"], ["c"]])
  let incident = @moonlog.Incident::new(
    "a",
    "memory",
    @moonlog.Opened,
    "down",
    0L,
  )
  assert_eq(@moonlog.sound(alarm, incident, desk), @moonlog.Heard)
  // `a` is the incident itself and is never asked; `b` succeeds.
  assert_eq(desk.delivered, ["b"])
}

///|
test "an alarm walks its tiers and stops after one takes the incident" {
  let desk = TestDesk::new(failing=["a", "b"])
  let alarm = @moonlog.Tiers::from([["a"], ["b"], ["c"]])
  let incident = @moonlog.Incident::new(
    "a",
    "memory",
    @moonlog.Opened,
    "down",
    0L,
  )
  assert_eq(@moonlog.sound(alarm, incident, desk), @moonlog.Heard)
  // `a` and `b` fail, `c` succeeds; `b` is not retried in a later tier.
  assert_eq(desk.delivered, ["c"])
}

///|
test "a star stands for every sink on the log route" {
  let desk = TestDesk::new(routes=["x", "y", "z"])
  let alarm = @moonlog.Tiers::from([["*"]])
  let incident = @moonlog.Incident::new(
    "a",
    "memory",
    @moonlog.Opened,
    "down",
    0L,
  )
  assert_eq(@moonlog.sound(alarm, incident, desk), @moonlog.Heard)
  assert_eq(desk.delivered, ["x", "y", "z"])
}

///|
test "a resting sink is left out and an unheard incident falls back to ignore" {
  let desk = TestDesk::new(routes=["x"], failing=["x"], resting=["x"])
  let alarm = @moonlog.Tiers::from([["x"]]).with_fallback(
    @moonlog.Fallback::Ignore,
  )
  let incident = @moonlog.Incident::new(
    "a",
    "memory",
    @moonlog.Opened,
    "down",
    0L,
  )
  assert_eq(@moonlog.sound(alarm, incident, desk), @moonlog.Unheard)
  assert_eq(desk.delivered, [])
}

///|
test "panic an unheard incident with a panic fallback raises" {
  let desk = TestDesk::new(failing=["a"])
  let alarm = @moonlog.Tiers::from([["a"]]).with_fallback(
    @moonlog.Fallback::Panic,
  )
  let incident = @moonlog.Incident::new(
    "a",
    "memory",
    @moonlog.Opened,
    "down",
    0L,
  )
  ignore(@moonlog.sound(alarm, incident, desk))
}
