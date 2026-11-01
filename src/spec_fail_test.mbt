// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The health cases of the shared specification, generated from
/// `scripts/serlog-cases/fail.json` by `scripts/gen_cases.py`: one test per
/// case, named with the case's number. Each step happens at a given second,
/// the sink says whether the write went through, and the machine must answer
/// whether it was tried, where it stands and what it told.
///
/// | step | machine |
/// |:--|:--|
/// | `up` fails | `down`, `opened` when told, next probe after `probe` |
/// | `down` before its probe | skipped, not tried |
/// | `down` at its probe | `probing`, one write decides |
/// | `probing` passes | `up`, `resolved` when the failure was told |
/// | `probing` fails | `down`, the wait doubled up to five minutes, `reminder` once `remind` has passed |
fn spec_nanos(seconds : Double) -> Int64 {
  (seconds * 1_000_000_000.0).to_int64()
}

///|
/// One step: the write goes ahead when the machine admits it, the sink answers
/// as `fails` says, and the phase the machine reports comes back.
fn spec_step(
  breaker : @moonlog.Breaker,
  at : Double,
  fails : Bool,
  remind : Double,
  tell : @moonlog.Tell,
) -> (Bool, @moonlog.Phase?) {
  let now = spec_nanos(at)
  let tried = breaker.admit(now)
  let phase = if !tried {
    None
  } else if fails {
    breaker.fault(now, "broken", spec_nanos(remind), tell)
  } else {
    breaker.pass(now)
  }
  (tried, phase)
}

///|
test "fail.json 1: one failure is told once and resolved after the probe" {
  let breaker = @moonlog.Breaker::new(spec_nanos(5.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    1.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, false)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    6.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 1L)
}

///|
test "fail.json 2: a failed probe doubles the wait" {
  let breaker = @moonlog.Breaker::new(spec_nanos(5.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    5.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    9.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, false)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    15.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 1L)
}

///|
test "fail.json 3: a long failure is told again after the reminder interval" {
  let breaker = @moonlog.Breaker::new(spec_nanos(5.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    10.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    5.0,
    true,
    10.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    15.0,
    true,
    10.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Reminder))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    35.0,
    false,
    10.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 0L)
}

///|
test "fail.json 4: probe 0 tries every record and only drops repeated reports" {
  let breaker = @moonlog.Breaker::new(spec_nanos(0.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    0.5,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    1.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 0L)
}

///|
test "fail.json 5: a silent slot never reports" {
  let breaker = @moonlog.Breaker::new(spec_nanos(5.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Silent,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    6.0,
    false,
    3600.0,
    @moonlog.Tell::Silent,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 0L)
}

///|
test "fail.json 6: a failure folded into another incident still reports recovery" {
  let breaker = @moonlog.Breaker::new(spec_nanos(5.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Folded,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    6.0,
    false,
    3600.0,
    @moonlog.Tell::Folded,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 0L)
}

///|
test "fail.json 7: the wait stops growing at five minutes" {
  let breaker = @moonlog.Breaker::new(spec_nanos(100.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    100.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    300.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    599.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, false)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    600.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 1L)
}

///|
test "fail.json 8: after recovery the wait starts over" {
  let breaker = @moonlog.Breaker::new(spec_nanos(5.0), 0L)
  let (tried, phase) = spec_step(
    breaker,
    0.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    5.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, None)
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    15.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  let (tried, phase) = spec_step(
    breaker,
    16.0,
    true,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Opened))
  assert_eq(breaker.health(), @moonlog.Health::Down)
  let (tried, phase) = spec_step(
    breaker,
    21.0,
    false,
    3600.0,
    @moonlog.Tell::Report,
  )
  assert_eq(tried, true)
  assert_eq(phase, Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  assert_eq(breaker.skipped(), 0L)
}
