// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The health vectors of the shared specification: each step happens at a
/// given second, the sink says whether the write went through, and the machine
/// must answer with whether it was tried, where it stands and what it told.
///
/// | step | machine |
/// |:--|:--|
/// | `up` fails | `down`, `opened` when told, next probe after `probe` |
/// | `down` before its probe | skipped, not tried |
/// | `down` at its probe | `probing`, one write decides |
/// | `probing` passes | `up`, `resolved` when the failure was told, gap back to the start |
/// | `probing` fails | `down`, gap doubled up to five minutes, `reminder` when `remind` has passed |
fn seconds(n : Double) -> Int64 {
  (n * 1_000_000_000.0).to_int64()
}

///|
/// One step of a health vector: the instant, what the sink says, and what the
/// machine must answer.
struct Step {
  at : Double
  fails : Bool
  tried : Bool
  health : Health
  phase : Phase?
}

///|
fn check_health(
  probe : Double,
  remind : Double,
  tell : Tell,
  steps : Array[Step],
) -> Unit raise {
  let breaker = Breaker::new(seconds(probe), 0L)
  for step in steps {
    let now = seconds(step.at)
    let tried = breaker.admit(now)
    assert_true(tried == step.tried)
    if tried {
      let phase = if step.fails {
        breaker.fault(now, "broken", seconds(remind), tell)
      } else {
        breaker.pass(now)
      }
      assert_true(phase == step.phase)
    }
    assert_true(breaker.health() == step.health)
  }
}

///|
test "one failure is told once and resolved after the probe" {
  check_health(5.0, 3600.0, Report, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 1.0, fails: false, tried: false, health: Down, phase: None, },
    { at: 6.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "a failed probe doubles the wait" {
  check_health(5.0, 3600.0, Report, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 5.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 9.0, fails: false, tried: false, health: Down, phase: None, },
    { at: 15.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "a long failure is told again after the reminder interval" {
  check_health(5.0, 10.0, Report, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 5.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 15.0, fails: true, tried: true, health: Down, phase: Some(Reminder), },
    { at: 35.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "probe 0 tries every record and only drops repeated reports" {
  check_health(0.0, 3600.0, Report, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 0.5, fails: true, tried: true, health: Down, phase: None, },
    { at: 1.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "a silent slot never reports" {
  check_health(5.0, 3600.0, Silent, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 6.0, fails: false, tried: true, health: Up, phase: None, },
  ])
}

///|
test "a failure folded into another incident still reports recovery" {
  check_health(5.0, 3600.0, Folded, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 6.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "the wait stops growing at five minutes" {
  check_health(100.0, 3600.0, Report, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 100.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 300.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 599.0, fails: false, tried: false, health: Down, phase: None, },
    { at: 600.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "after recovery the wait starts over" {
  check_health(5.0, 3600.0, Report, [
    { at: 0.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 5.0, fails: true, tried: true, health: Down, phase: None, },
    { at: 15.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
    { at: 16.0, fails: true, tried: true, health: Down, phase: Some(Opened), },
    { at: 21.0, fails: false, tried: true, health: Up, phase: Some(Resolved), },
  ])
}

///|
test "skips are counted, over the slot's life and since the failure" {
  let breaker = Breaker::new(seconds(5.0), 0L)
  assert_true(breaker.admit(0L))
  ignore(breaker.fault(0L, "broken", seconds(3600.0), Silent))
  assert_false(breaker.admit(seconds(1.0)))
  assert_false(breaker.admit(seconds(2.0)))
  assert_eq(breaker.skipped(), 2L)
  assert_eq(breaker.skipped_now(), 2L)
  assert_true(breaker.wait(seconds(1.0)) == seconds(4.0))
  assert_true(breaker.resting(seconds(1.0)))
}
