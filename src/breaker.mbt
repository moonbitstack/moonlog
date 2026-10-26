// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Whether a sink is working.
pub(all) enum Health {
  Up
  Down
  Probing
} derive(Eq, Debug)

///|
pub extend Health with Eq::{equal, not_equal}

///|
pub extend Health with Debug::{to_repr}

///|
/// The name used in configuration, status and the shared vectors.
pub fn Health::name(self : Health) -> StringView {
  match self {
    Up => "up"
    Down => "down"
    Probing => "probing"
  }
}

///|
/// How a failure is told.
pub(all) enum Tell {
  Report
  Silent
  Folded
} derive(Eq, Debug)

///|
pub extend Tell with Eq::{equal, not_equal}

///|
pub extend Tell with Debug::{to_repr}

///|
/// A slot's health: up, down, or one write testing whether it works again.
///
/// It knows no I/O and reads no clock — every method takes the instant — which
/// is what makes the machine checkable against vectors instead of against a
/// stopwatch.
pub struct Breaker {
  probe : Int64
  mut health : Health
  mut gap : Int64
  mut next : Int64
  mut told : Int64?
  mut since : Int64
  mut opened : Int64
  mut opened_at : Int64
  mut skipped : Int64
  mut error : String?
}

///|
/// A healthy machine that first probes `probe` nanoseconds after a failure.
pub fn Breaker::new(probe : Int64, now : Int64) -> Breaker {
  {
    probe,
    health: Up,
    gap: probe,
    next: now,
    told: None,
    since: now,
    opened: 0L,
    opened_at: 0L,
    skipped: 0L,
    error: None,
  }
}

///|
/// Where the sink stands now: `Up`, `Down`, or `Probing` while a trial write is
/// due.
pub fn Breaker::health(self : Breaker) -> Health {
  self.health
}

///|
/// Records skipped while down, over the slot's life.
pub fn Breaker::skipped(self : Breaker) -> Int64 {
  self.skipped
}

///|
/// Records skipped since the current failure began.
pub fn Breaker::skipped_now(self : Breaker) -> Int64 {
  self.skipped - self.opened_at
}

///|
/// When the current health began.
pub fn Breaker::since(self : Breaker) -> Int64 {
  self.since
}

///|
/// The latest error.
pub fn Breaker::error(self : Breaker) -> String? {
  self.error
}

///|
/// When the current failure began, which is what an incident calls `since`;
/// `since` itself moves when the sink recovers.
pub fn Breaker::failed_since(self : Breaker) -> Int64 {
  self.opened
}

///|
/// Whether a write may go ahead at `now`: turns a due `Down` into `Probing`,
/// and counts a skip otherwise.
pub fn Breaker::admit(self : Breaker, now : Int64) -> Bool {
  match self.health {
    Up => true
    Down =>
      if now >= self.next {
        self.health = Probing
        true
      } else {
        self.skipped = self.skipped + 1
        false
      }
    Probing => false
  }
}

///|
/// Whether a sink is skipped at `now` without counting anything, for choosing
/// alarm targets.
pub fn Breaker::resting(self : Breaker, now : Int64) -> Bool {
  match self.health {
    Up => false
    Down => now < self.next
    Probing => true
  }
}

///|
/// How long until the next probe.
pub fn Breaker::wait(self : Breaker, now : Int64) -> Int64 {
  if self.next > now {
    self.next - now
  } else {
    0L
  }
}

///|
/// A write went through; `Resolved` when the failure had been told.
pub fn Breaker::pass(self : Breaker, now : Int64) -> Phase? {
  if self.health == Up {
    return None
  }
  self.health = Up
  self.gap = self.probe
  self.since = now
  self.error = None
  match self.told {
    Some(_) => {
      self.told = None
      Some(Resolved)
    }
    None => None
  }
}

///|
/// A write failed; `Opened` or `Reminder` when that is to be told.
pub fn Breaker::fault(
  self : Breaker,
  now : Int64,
  error : String,
  remind : Int64,
  tell : Tell,
) -> Phase? {
  self.error = Some(error)
  match self.health {
    Up => {
      self.health = Down
      self.gap = self.probe
      self.next = now + self.gap
      self.since = now
      self.opened = now
      self.opened_at = self.skipped
      match tell {
        Report => {
          self.told = Some(now)
          Some(Opened)
        }
        Folded => {
          self.told = Some(now)
          None
        }
        Silent => None
      }
    }
    Probing => {
      self.health = Down
      let doubled = self.gap * 2L
      self.gap = if doubled > longest_probe { longest_probe } else { doubled }
      self.next = now + self.gap
      match self.told {
        Some(at) =>
          if tell == Report && now - at >= remind {
            self.told = Some(now)
            Some(Reminder)
          } else {
            None
          }
        None => None
      }
    }
    Down => None
  }
}

///|
/// Five minutes: the longest a failed sink waits between probes.
///
/// The cap the health cases stop at: the wait doubles up to this and no
/// further, however long the outage lasts.
pub let longest_probe : Int64 = 300_000_000_000L
