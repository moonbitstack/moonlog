// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The alarm cases of the shared specification, generated from
/// `scripts/serlog-cases/alarm.json` by `scripts/gen_cases.py`: one test per
/// case, named with the case's number. The failing sink is never asked, `*`
/// stands for every sink on the log route, a resting sink is left out, and one
/// success ends the walk.
struct SpecStand {
  logs : Array[String]
  down : Array[String]
  results : Map[String, Bool]
  asked : Array[String]
}

///|
fn spec_stand(
  logs : Array[String],
  down : Array[String],
  results : Array[(String, Bool)],
) -> SpecStand {
  let answers : Map[String, Bool] = Map([])
  for pair in results {
    answers[pair.0] = pair.1
  }
  { logs, down, results: answers, asked: [], }
}

///|
pub impl @moonlog.Desk for SpecStand with fn logs(self) {
  self.logs
}

///|
pub impl @moonlog.Desk for SpecStand with fn resting(self, name) {
  self.down.contains(name)
}

///|
pub impl @moonlog.Desk for SpecStand with fn deliver(self, name, _record) {
  self.asked.push(name)
  match self.results.get(name) {
    Some(true) => Ok(())
    _ => Err("refused")
  }
}

///|
/// One walk: what the alarm made of the incident, which sinks it asked, and
/// which failures the incident ended up carrying.
fn spec_walk(
  failing : String,
  tiers : Array[Array[String]],
  stand : SpecStand,
) -> (@moonlog.Outcome, Array[String], Array[String]) {
  let incident = @moonlog.Incident::new(
    failing,
    "sink",
    @moonlog.Phase::Opened,
    "broken",
    0L,
  )
  let outcome = @moonlog.sound(@moonlog.Tiers::from(tiers), incident, stand)
  let failures : Array[String] = []
  for failure in incident.failures {
    failures.push(failure.sink)
  }
  (outcome, stand.asked, failures)
}

///|
test "alarm.json 1: the first tier where one sink takes it ends the walk" {
  let stand = spec_stand(["console-1", "app", "loki"], [], [
    ("console-1", true),
    ("loki", false),
    ("stderr", true),
  ])
  let (outcome, asked, failures) = spec_walk("app", [["*"], ["stderr"]], stand)
  assert_eq(outcome, @moonlog.Outcome::Heard)
  assert_eq(asked, ["console-1", "loki"])
  assert_eq(failures, ["app", "loki"])
}

///|
test "alarm.json 2: when a whole tier fails the next one gets it" {
  let stand = spec_stand(["a", "b"], [], [("b", false), ("stderr", true)])
  let (outcome, asked, failures) = spec_walk("a", [["*"], ["stderr"]], stand)
  assert_eq(outcome, @moonlog.Outcome::Heard)
  assert_eq(asked, ["b", "stderr"])
  assert_eq(failures, ["a", "b"])
}

///|
test "alarm.json 3: resting sinks are left out" {
  let stand = spec_stand([], ["loki"], [("mail", true)])
  let (outcome, asked, failures) = spec_walk(
    "app",
    [["loki", "mail"], ["stderr"]],
    stand,
  )
  assert_eq(outcome, @moonlog.Outcome::Heard)
  assert_eq(asked, ["mail"])
  assert_eq(failures, ["app"])
}

///|
test "alarm.json 4: the failing sink is never asked, and an empty tier is skipped" {
  let stand = spec_stand([], [], [("mail", true)])
  let (outcome, asked, failures) = spec_walk(
    "loki",
    [["loki"], ["mail"]],
    stand,
  )
  assert_eq(outcome, @moonlog.Outcome::Heard)
  assert_eq(asked, ["mail"])
  assert_eq(failures, ["loki"])
}

///|
test "alarm.json 5: nobody takes it" {
  let stand = spec_stand([], [], [("a", false), ("b", false)])
  let (outcome, asked, failures) = spec_walk("x", [["a"], ["b"]], stand)
  assert_eq(outcome, @moonlog.Outcome::Unheard)
  assert_eq(asked, ["a", "b"])
  assert_eq(failures, ["x", "a", "b"])
}

///|
test "alarm.json 6: a sink tried in an earlier tier is not asked again" {
  let stand = spec_stand([], [], [("a", false), ("b", false), ("c", true)])
  let (outcome, asked, failures) = spec_walk(
    "x",
    [["a", "b"], ["b", "c"]],
    stand,
  )
  assert_eq(outcome, @moonlog.Outcome::Heard)
  assert_eq(asked, ["a", "b", "c"])
  assert_eq(failures, ["x", "a", "b"])
}

///|
test "alarm.json 7: the star expands once and drops the failing sink" {
  let stand = spec_stand(["x", "a"], [], [("a", true)])
  let (outcome, asked, failures) = spec_walk("x", [["*", "a"]], stand)
  assert_eq(outcome, @moonlog.Outcome::Heard)
  assert_eq(asked, ["a"])
  assert_eq(failures, ["x"])
}
