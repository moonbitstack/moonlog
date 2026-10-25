// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The alarm vectors of the shared specification: the failing sink is never
/// asked, `*` stands for every sink on the log route, a resting sink is left
/// out, and one success ends the walk.
struct Stand {
  logs_ : Array[String]
  down : Array[String]
  results : Map[String, Bool]
  asked : Array[String]
  tiers : Array[Array[String]]
  failed : Array[String]
}

///|
fn Stand::new(
  logs : Array[String],
  down : Array[String],
  tiers : Array[Array[String]],
) -> Stand {
  { logs_: logs, down, results: Map([]), asked: [], tiers, failed: [], }
}

///|
fn Stand::says(self : Stand, name : String, ok : Bool) -> Stand {
  self.results[name] = ok
  self
}

///|
pub impl Desk for Stand with fn logs(self) {
  self.logs_
}

///|
pub impl Desk for Stand with fn resting(self, name) {
  self.down.contains(name)
}

///|
pub impl Desk for Stand with fn deliver(self, name, _record) {
  self.asked.push(name)
  match self.results.get(name) {
    Some(true) => Ok(())
    _ => {
      self.failed.push(name)
      Err("refused")
    }
  }
}

///|
pub extend Stand with Desk::{logs, resting, deliver}

///|
/// What one walk did.
struct Walk {
  outcome : Outcome
  asked : Array[String]
  failures : Array[String]
}

///|
fn walk(failing : String, stand : Stand) -> Walk {
  let alarm = Tiers::from(stand.tiers)
  let incident = Incident::new(failing, "sink", Opened, "broken", 0L)
  let outcome = sound(alarm, incident, stand)
  let failures : Array[String] = []
  for failure in incident.failures {
    failures.push(failure.sink)
  }
  { outcome, asked: stand.asked, failures, }
}

///|
test "the first tier where one sink takes it ends the walk" {
  let stand = Stand::new(["console-1", "app", "loki"], [], [["*"], ["stderr"]])
    .says("console-1", true)
    .says("loki", false)
    .says("stderr", true)
  let result = walk("app", stand)
  assert_true(result.outcome == Heard)
  assert_eq(join(result.asked, ","), "console-1,loki")
  assert_eq(join(result.failures, ","), "app,loki")
}

///|
test "when a whole tier fails the next one gets it" {
  let stand = Stand::new(["a", "b"], [], [["*"], ["stderr"]])
    .says("b", false)
    .says("stderr", true)
  let result = walk("a", stand)
  assert_true(result.outcome == Heard)
  assert_eq(join(result.asked, ","), "b,stderr")
  assert_eq(join(result.failures, ","), "a,b")
}

///|
test "resting sinks are left out" {
  let stand = Stand::new([], ["loki"], [["loki", "mail"], ["stderr"]]).says(
    "mail", true,
  )
  let result = walk("app", stand)
  assert_true(result.outcome == Heard)
  assert_eq(join(result.asked, ","), "mail")
  assert_eq(join(result.failures, ","), "app")
}

///|
test "the failing sink is never asked, and an empty tier is skipped" {
  let stand = Stand::new([], [], [["loki"], ["mail"]]).says("mail", true)
  let result = walk("loki", stand)
  assert_true(result.outcome == Heard)
  assert_eq(join(result.asked, ","), "mail")
  assert_eq(join(result.failures, ","), "loki")
}

///|
test "nobody takes it" {
  let stand = Stand::new([], [], [["a"], ["b"]])
    .says("a", false)
    .says("b", false)
  let result = walk("x", stand)
  assert_true(result.outcome == Unheard)
  assert_eq(join(result.asked, ","), "a,b")
  assert_eq(join(result.failures, ","), "x,a,b")
}

///|
test "a sink tried in an earlier tier is not asked again" {
  let stand = Stand::new([], [], [["a", "b"], ["b", "c"]])
    .says("a", false)
    .says("b", false)
    .says("c", true)
  let result = walk("x", stand)
  assert_true(result.outcome == Heard)
  assert_eq(join(result.asked, ","), "a,b,c")
  assert_eq(join(result.failures, ","), "x,a,b")
}

///|
test "the star expands once and drops the failing sink" {
  let stand = Stand::new(["x", "a"], [], [["*", "a"]]).says("a", true)
  let result = walk("x", stand)
  assert_true(result.outcome == Heard)
  assert_eq(join(result.asked, ","), "a")
  assert_eq(join(result.failures, ","), "x")
}

///|
test "an incident becomes a record with the phase on it" {
  let incident = Incident::new("loki", "loki", Opened, "connection refused", 0L)
  let record = incident.describe()
  assert_true(record.level == error)
  assert_eq(record.msg, "sink `loki` failed: connection refused")
  assert_true(record.field("phase") is Some(Value::Str("opened")))
  assert_true(record.field("sink") is Some(Value::Str("loki")))
  let resolved = Incident::new("loki", "loki", Resolved, "", 5_000_000_000L)
  resolved.at = 65_000_000_000L
  assert_true(resolved.describe().level == info)
  assert_eq(resolved.describe().msg, "sink `loki` works again after 60s")
}
