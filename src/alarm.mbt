// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which report of an incident this is.
pub(all) enum Phase {
  Opened
  Reminder
  Resolved
} derive(Eq, Debug)

///|
pub extend Phase with Eq::{equal, not_equal}

///|
pub extend Phase with Debug::{to_repr}

///|
/// The name used in a record's `phase` field and in the shared vectors.
pub fn Phase::name(self : Phase) -> StringView {
  match self {
    Opened => "opened"
    Reminder => "reminder"
    Resolved => "resolved"
  }
}

///|
/// What an alarm does when no tier took the incident.
pub(all) enum Fallback {
  Panic
  Ignore
} derive(Eq, Debug)

///|
pub extend Fallback with Eq::{equal, not_equal}

///|
pub extend Fallback with Debug::{to_repr}

///|
/// One failed delivery, on the way to an alarm.
pub(all) struct Failure {
  sink : String
  error : String
  at : Int64
}

///|
/// A sink's failure, from the first error to its recovery.
///
/// A phase is a fresh incident each time: `Opened` when the sink first failed,
/// `Reminder` while it is still down, `Resolved` when it writes again. Each
/// carries what is known at that moment, which is why the type is a value and
/// not a handle.
pub(all) struct Incident {
  sink : String
  kind : String
  phase : Phase
  error : String
  failures : Array[Failure]
  mut skipped : Int64
  mut dropped : Int64
  mut since : Int64
  /// When this report was made; `since` is when the failure began.
  mut at : Int64
}

///|
/// A fresh incident: `sink`, a sink of `kind`, failed with `error` at `now`, in
/// `phase`.
pub fn Incident::new(
  sink : String,
  kind : String,
  phase : Phase,
  error : String,
  now : Int64,
) -> Incident {
  {
    sink,
    kind,
    phase,
    error,
    failures: [{ sink, error, at: now, }],
    skipped: 0L,
    dropped: 0L,
    since: now,
    at: now,
  }
}

///|
/// The record an incident becomes: `error` when something failed, `info` when
/// something works again, with the failures on one field.
pub fn Incident::describe(
  self : Incident,
  target~ : String = "moonlog",
) -> Record {
  let (level, msg) = match self.phase {
    Opened => (error, "sink `" + self.sink + "` failed: " + self.error)
    Reminder =>
      (error, "sink `" + self.sink + "` is still failing: " + self.error)
    Resolved => {
      let seconds = floor_div(self.at - self.since, 1_000_000_000L)
      (
        info,
        "sink `" +
        self.sink +
        "` works again after " +
        seconds.to_string() +
        "s",
      )
    }
  }
  let failures = StringBuilder()
  for i, failure in self.failures {
    if i > 0 {
      failures.write_string("; ")
    }
    failures.write_string(failure.sink)
    failures.write_string(": ")
    failures.write_string(failure.error)
  }
  Record::of(level, target, msg).sets([
    ("sink", Value::of_str(self.sink)),
    ("kind", Value::of_str(self.kind)),
    ("phase", Value::of_str(self.phase.name())),
    ("failures", Value::of_str(failures.to_string())),
    ("skipped", Value::of_long(self.skipped)),
    ("dropped", Value::of_long(self.dropped)),
    ("since", Value::of_long(self.since)),
  ])
}

///|
/// Chooses where an incident goes.
///
/// The runtime walks the tiers, skips the failing sink and any that are resting,
/// and stops at the first tier where one sink took the record — so an
/// implementation only has to say which sinks to try.
pub(open) trait Alarm {
  /// The tiers of sink names to try for this incident, in order.
  fn route(Self, Incident) -> Array[Array[String]]
  /// What happens when no tier took the incident.
  fn fallback(Self) -> Fallback
  /// How long a sink may stay down before it is reported again, in nanoseconds.
  fn remind(Self) -> Int64
}

///|
/// What the alarm walk needs from the sinks around it.
pub(open) trait Desk {
  /// The sinks on the log route, which `*` stands for.
  fn logs(Self) -> Array[String]
  /// Whether a sink is down and not yet due for a probe.
  fn resting(Self, String) -> Bool
  /// Writes `record` to the named sink at once, bypassing its queue. `Err` is
  /// what the sink said, or that no sink has that name.
  fn deliver(Self, String, Record) -> Result[Unit, String]
}

///|
/// Fixed tiers of sink names: `[["loki"], ["oncall"], ["stderr"]]`.
pub struct Tiers {
  tiers : Array[Array[String]]
  fallback : Fallback
  remind : Int64
}

///|
/// One hour: how long an alarm stays quiet about a sink that is still down.
///
/// The interval the alarm cases are written with, so a tier built with the
/// defaults reports a long outage at the same moments they describe.
pub let remind_default : Int64 = 3_600_000_000_000L

///|
/// The default alarm: standard error alone, one hour between reminders.
pub fn Tiers::new() -> Tiers {
  { tiers: [["stderr"]], fallback: Ignore, remind: remind_default, }
}

///|
/// Tiers of names, tried in order.
pub fn Tiers::from(tiers : Array[Array[String]]) -> Tiers {
  { tiers, fallback: Ignore, remind: remind_default, }
}

///|
/// The same tiers, with `fallback` deciding what happens when no tier took the
/// incident.
pub fn Tiers::with_fallback(self : Tiers, fallback : Fallback) -> Tiers {
  { tiers: self.tiers, fallback, remind: self.remind, }
}

///|
/// How long a sink may stay down before it is reported again.
pub fn Tiers::with_remind(self : Tiers, remind : Int64) -> Tiers {
  { tiers: self.tiers, fallback: self.fallback, remind, }
}

///|
/// The tiers themselves.
pub fn Tiers::tiers(self : Tiers) -> Array[Array[String]] {
  self.tiers
}

///|
pub impl Alarm for Tiers with fn route(self, _incident) {
  self.tiers
}

///|
pub impl Alarm for Tiers with fn fallback(self) {
  self.fallback
}

///|
pub impl Alarm for Tiers with fn remind(self) {
  self.remind
}

///|
pub extend Tiers with Alarm::{route, fallback, remind}

///|
/// How an alarm walk ended.
pub(all) enum Outcome {
  Heard
  Unheard
} derive(Eq, Debug)

///|
pub extend Outcome with Eq::{equal, not_equal}

///|
pub extend Outcome with Debug::{to_repr}

///|
/// Delivers `incident` through `alarm`'s tiers, adding every failed delivery to
/// it.
///
/// The failing sink is never asked. `*` stands for every sink on the log route.
/// A sink already tried is not tried again, and a resting one is left out.
/// One success ends the walk; when no tier takes it, nothing more happens here.
pub fn sound(alarm : &Alarm, incident : Incident, desk : &Desk) -> Outcome {
  let tried : Array[String] = [incident.sink]
  for tier in alarm.route(incident) {
    let names : Array[String] = []
    for name in tier {
      let candidates = if name == "*" { desk.logs() } else { [name] }
      for candidate in candidates {
        if !tried.contains(candidate) &&
          !names.contains(candidate) &&
          !desk.resting(candidate) {
          names.push(candidate)
        }
      }
    }
    if names.length() == 0 {
      continue
    }
    let record = incident.describe()
    let mut heard = false
    for name in names {
      match desk.deliver(name, record) {
        Ok(_) => heard = true
        Err(error) =>
          incident.failures.push({ sink: name, error, at: incident.since, })
      }
      tried.push(name)
    }
    if heard {
      return Heard
    }
  }
  match alarm.fallback() {
    Ignore => ()
    Panic => panic()
  }
  Unheard
}
