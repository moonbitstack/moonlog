// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a full queue does with a record that arrives.
pub(all) enum Full {
  Drop
  Block
} derive(Eq, Debug)

///|
pub extend Full with Eq::{equal, not_equal}

///|
pub extend Full with Debug::{to_repr}

///|
/// A buffer in front of a sink, written in batches.
///
/// Without a runtime to hand, the buffer is drained by the hub: when it holds
/// `batch` records, when `wait` has passed since the first one, or at `flush`.
/// That is the policy a background task would follow, with the clock still in
/// the caller's hands.
pub(all) struct Queue {
  size : Int32
  batch : Int32
  wait : Int64
  full : Full
}

///|
/// Holds `size` records, written 1000 at a time or a second after the first.
pub fn Queue::new(size~ : Int32) -> Queue {
  { size, batch: 1000, wait: 1_000_000_000L, full: Drop, }
}

///|
pub fn Queue::batch(self : Queue, batch : Int32) -> Queue {
  { size: self.size, batch, wait: self.wait, full: self.full, }
}

///|
pub fn Queue::wait(self : Queue, wait : Int64) -> Queue {
  { size: self.size, batch: self.batch, wait, full: self.full, }
}

///|
pub fn Queue::full(self : Queue, full : Full) -> Queue {
  { size: self.size, batch: self.batch, wait: self.wait, full, }
}

///|
/// What a slot does when its sink fails.
pub(all) enum OnFail {
  Panic
  Ignore
  Alarm(&Alarm)
}

///|
/// What went wrong on the way to a sink, and whether the failure is one the
/// alarm policy has been told about.
pub(all) struct Fault {
  error : String
  phase : Phase?
}

///|
/// What a delivery did: the failure it met, if any, and the phase an alarm is
/// owed, if any. A recovery is a phase too, which is why this is not a `Result`.
pub(all) struct Report {
  fault : Fault?
  phase : Phase?
}

///|
/// A slot's state, for a status page.
pub(all) struct Status {
  name : String
  health : Health
  skipped : Int64
  dropped : Int64
  suppressed : Int64
  since : Int64
  error : String?
}

///|
/// One sink with the settings around it: name, filter, processors, layout,
/// colour, queue, retries, health and the policy for failure.
///
/// A slot is a value an application builds and hands to a hub. Nothing about it
/// is process-wide, so two hubs can hold two slots writing the same file in two
/// formats and neither knows about the other.
pub struct Slot {
  name : String
  sink : &Sink
  mut filter : Filter?
  chain : Array[&Processor]
  mut layout : &Layout
  mut layout_given : Bool
  mut colour : Bool
  mut alarm_only : Bool
  mut on_fail : OnFail
  mut queue : Queue?
  mut retries : Int32
  mut breaker : Breaker
  mut dropped : Int64
  suppressed : Int64
  buffered : Array[Record]
  mut buffered_at : Int64
}

///|
/// A slot named `name` writing to `sink`, with the library's own pattern as its
/// layout until one is given.
pub fn Slot::new(sink : &Sink, name~ : String) -> Slot {
  let layout : &Layout = default_layout()
  {
    name,
    sink,
    filter: None,
    chain: [],
    layout,
    layout_given: false,
    colour: false,
    alarm_only: false,
    on_fail: Ignore,
    queue: None,
    retries: 0,
    breaker: Breaker::new(5_000_000_000L, 0L),
    dropped: 0L,
    suppressed: 0L,
    buffered: [],
    buffered_at: 0L,
  }
}

///|
/// The pattern this library writes when a slot is given no layout.
fn default_layout() -> Pattern {
  Pattern::parse(Profile::Serlog.pattern()) catch {
    _ => panic()
  }
}

///|
/// Takes only what `filter` lets through.
pub fn Slot::filter(self : Slot, filter : Filter) -> Slot {
  self.filter = Some(filter)
  self
}

///|
/// Takes only `min` and above.
pub fn Slot::at(self : Slot, min : Level) -> Slot {
  self.filter(Filter::at(min))
}

///|
/// Adds a step that runs for this slot only.
pub fn Slot::process(self : Slot, step : &Processor) -> Slot {
  self.chain.push(step)
  self
}

///|
/// Lays entries out this way instead of the profile's pattern.
pub fn Slot::layout(self : Slot, layout : &Layout) -> Slot {
  self.layout = layout
  self.layout_given = true
  self
}

///|
/// What happens when the sink fails.
fn Slot::policy(self : Slot) -> OnFail {
  self.on_fail
}

///|
/// Whether this slot's lines are coloured.
pub fn Slot::coloured(self : Slot, colour : Bool) -> Slot {
  self.colour = colour
  self
}

///|
/// Keeps it off the log route, for alarms only.
pub fn Slot::alarm_only(self : Slot) -> Slot {
  self.alarm_only = true
  self
}

///|
/// What happens when the sink fails.
pub fn Slot::on_fail(self : Slot, on_fail : OnFail) -> Slot {
  self.on_fail = on_fail
  self
}

///|
/// Runs the sink behind `queue`.
pub fn Slot::queue(self : Slot, queue : Queue) -> Slot {
  self.queue = Some(queue)
  self
}

///|
/// Tries a failed write this many more times, without pausing.
pub fn Slot::retries(self : Slot, retries : Int32) -> Slot {
  self.retries = retries
  self
}

///|
/// First wait before probing a failed sink; it doubles up to five minutes.
pub fn Slot::probe(self : Slot, probe : Int64) -> Slot {
  self.breaker = Breaker::new(probe, 0L)
  self
}

///|
/// The slot's name.
pub fn Slot::name(self : Slot) -> String {
  self.name
}

///|
/// The layout the hub's profile chose, when the slot was given none.
fn Slot::adopt(self : Slot, layout : &Layout) -> Unit {
  if !self.layout_given {
    self.layout = layout
  }
}

///|
/// Where it stands.
pub fn Slot::status(self : Slot) -> Status {
  {
    name: self.name,
    health: self.breaker.health(),
    skipped: self.breaker.skipped(),
    dropped: self.dropped,
    suppressed: self.suppressed,
    since: self.breaker.since(),
    error: self.breaker.error(),
  }
}

///|
/// When the current failure began, for the incident an alarm carries.
pub fn Slot::failed_since(self : Slot) -> Int64 {
  self.breaker.failed_since()
}

///|
/// Whether the slot is resting at `now`, so an alarm leaves it out.
fn Slot::resting(self : Slot, now : Int64) -> Bool {
  self.breaker.resting(now)
}

///|
/// Whether records at this level and target reach the sink at all.
fn Slot::wants(
  self : Slot,
  level : Level,
  target : String,
  msg : String,
) -> Bool {
  match self.filter {
    Some(filter) => filter.admits(level, target, msg)
    None => true
  }
}

///|
/// Runs the slot's steps over `record`, or `None` when one drops it.
fn Slot::refine(self : Slot, record : Record, env : Env) -> Record? {
  run_chain(self.chain, record, env)
}

///|
/// The line this slot would write for `record`.
fn Slot::line(self : Slot, record : Record, scene : Scene) -> String {
  self.layout.render(record, scene.coloured(self.colour))
}

///|
/// Takes a record the slot wants: straight to the sink when it runs direct, or
/// into the queue.
fn Slot::send(
  self : Slot,
  record : Record,
  scene : Scene,
  now : Int64,
) -> Report {
  match self.queue {
    None => self.deliver(record, scene, now)
    Some(queue) => {
      if self.buffered.length() >= queue.size {
        match queue.full {
          Drop => {
            self.dropped = self.dropped + 1
            return { fault: None, phase: None, }
          }
          Block => {
            let report = self.flush(scene, now)
            if report.fault is Some(_) {
              return report
            }
          }
        }
      }
      if self.buffered.length() == 0 {
        self.buffered_at = now
      }
      self.buffered.push(record)
      if self.buffered.length() >= queue.batch ||
        now - self.buffered_at >= queue.wait {
        self.flush(scene, now)
      } else {
        { fault: None, phase: None, }
      }
    }
  }
}

///|
/// Writes what the queue holds. A batch that fails is kept and tried again at
/// the next probe; nothing is lost because a sink had a bad second.
fn Slot::flush(self : Slot, scene : Scene, now : Int64) -> Report {
  if self.buffered.length() == 0 {
    return { fault: None, phase: None, }
  }
  if !self.breaker.admit(now) {
    return { fault: None, phase: None, }
  }
  let entries : Array[Entry] = []
  for record in self.buffered {
    entries.push({ record, line: self.line(record, scene), })
  }
  let mut tried = 0
  while true {
    let mut failed = None
    for entry in entries {
      match self.sink.write(entry) {
        Ok(_) => ()
        Err(error) => {
          failed = Some(error)
          break
        }
      }
    }
    match failed {
      None => {
        let phase = self.breaker.pass(now)
        self.buffered.clear()
        return { fault: None, phase, }
      }
      Some(error) =>
        if tried >= self.retries {
          let phase = self.breaker.fault(
            now,
            error,
            remind_of(self.on_fail),
            tell_of(self.on_fail),
          )
          return { fault: Some({ error, phase, }), phase, }
        } else {
          tried = tried + 1
        }
    }
  }
  { fault: None, phase: None, }
}

///|
/// Writes `record` to the sink now, whatever the queue holds, and drives the
/// health machine from what the sink says.
fn Slot::deliver(
  self : Slot,
  record : Record,
  scene : Scene,
  now : Int64,
) -> Report {
  if !self.breaker.admit(now) {
    return { fault: None, phase: None, }
  }
  let entry = { record, line: self.line(record, scene), }
  match self.attempt(entry) {
    Ok(_) => {
      let phase = self.breaker.pass(now)
      { fault: None, phase, }
    }
    Err(error) => {
      let phase = self.breaker.fault(
        now,
        error,
        remind_of(self.on_fail),
        tell_of(self.on_fail),
      )
      { fault: Some({ error, phase, }), phase, }
    }
  }
}

///|
fn Slot::attempt(self : Slot, entry : Entry) -> Result[Unit, String] {
  let mut tries = 0
  while true {
    match self.sink.write(entry) {
      Ok(_) => return Ok(())
      Err(error) =>
        if tries >= self.retries {
          return Err(error)
        } else {
          tries = tries + 1
        }
    }
  }
  Ok(())
}

///|
/// The reminder interval of an alarm, in nanoseconds; a slot without one never
/// reminds.
fn remind_of(on_fail : OnFail) -> Int64 {
  match on_fail {
    Alarm(alarm) => alarm.remind()
    _ => 9_000_000_000_000_000_000L
  }
}

///|
/// How a failure under this policy is told.
fn tell_of(on_fail : OnFail) -> Tell {
  match on_fail {
    Alarm(_) => Report
    _ => Silent
  }
}

///|
/// Runs a chain; `None` when a step dropped the record.
fn run_chain(chain : Array[&Processor], record : Record, env : Env) -> Record? {
  let mut current = record
  for step in chain {
    match step.process(current, env) {
      Some(next) => current = next
      None => return None
    }
  }
  Some(current)
}
