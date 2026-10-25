// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole of a running logger: a global filter, a chain of steps every
/// record goes through, a table of slots, and the identity and clock that the
/// application handed in.
///
/// There is no process-wide hub. An application builds one and passes the
/// `Logger` values that write to it to the libraries it uses; a library that was
/// handed none writes nothing.
pub struct Hub {
  identity : Identity
  profile : Profile
  mut filter : Filter
  chain : Array[&Processor]
  slots : Array[Slot]
  layout : &Layout
  clock : () -> Int64
  mut seq : Int64
}

///|
/// A hub at `profile`, writing what the filter lets through.
///
/// `clock` answers nanoseconds since the epoch. Without one every record carries
/// 0, which is honest — this library never reads a clock — and every test says
/// what instant it means.
pub fn Hub::new(
  identity~ : Identity = Identity::new(),
  profile~ : Profile = Profile::Serlog,
  clock~ : () -> Int64 = fn() { 0L },
  filter~ : Filter? = None,
) -> Hub {
  let chosen = match filter {
    Some(given) => given
    None => Filter::at(profile.level())
  }
  {
    identity,
    profile,
    filter: chosen,
    chain: [],
    slots: [],
    layout: profile_layout(profile),
    clock,
    seq: 0L,
  }
}

///|
/// The pattern a profile uses as its default line.
fn profile_layout(profile : Profile) -> Pattern {
  Pattern::parse(profile.pattern()) catch {
    _ => default_layout()
  }
}

///|
/// The instant the hub is working at, from the clock it was given.
pub fn Hub::now(self : Hub) -> Int64 {
  (self.clock)()
}

///|
/// The identity records are stamped with.
pub fn Hub::identity(self : Hub) -> Identity {
  self.identity
}

///|
/// The profile in force.
pub fn Hub::profile(self : Hub) -> Profile {
  self.profile
}

///|
/// The scene a line is written in: this hub's vocabulary, this hub's identity.
pub fn Hub::scene(self : Hub) -> Scene {
  Scene::new(identity=self.identity, profile=self.profile, colour=false)
}

///|
/// The filter now in force.
pub fn Hub::filter(self : Hub) -> Filter {
  self.filter
}

///|
/// Replaces the global filter; takes effect at once.
pub fn Hub::set_filter(self : Hub, filter : Filter) -> Unit {
  self.filter = filter
}

///|
/// Lets through `min` and above for every target.
pub fn Hub::set_level(self : Hub, min : Level) -> Unit {
  self.filter = Filter::at(min)
}

///|
/// Whether a record at `level` could pass, before its target or message is
/// known. Worth asking before building a message that costs something.
pub fn Hub::enabled(self : Hub, level : Level) -> Bool {
  match self.filter.lowest() {
    Some(min) => level.at_least(min)
    None => false
  }
}

///|
/// Adds a step to the global chain, which runs before any slot sees the record.
pub fn Hub::process(self : Hub, step : &Processor) -> Unit {
  self.chain.push(step)
}

///|
/// Registers a slot and answers the name it took.
///
/// A second slot with the same name is refused, and so is the name `*`, which
/// would make an alarm tier ambiguous.
pub fn Hub::add(self : Hub, slot : Slot) -> String raise Refused {
  let name = slot.name()
  if name == "*" {
    raise refuse(0, name, "a name other than `*`")
  }
  for taken in self.slots {
    if taken.name() == name {
      raise refuse(0, name, "a name no other slot has")
    }
  }
  slot.adopt(self.layout)
  self.slots.push(slot)
  name
}

///|
/// Takes a slot out by name, after writing what its queue holds.
pub fn Hub::remove(self : Hub, name : String) -> Bool {
  let mut found = false
  let kept : Array[Slot] = []
  for slot in self.slots {
    if slot.name() == name {
      found = true
      ignore(slot.flush(self.scene(), self.now()))
    } else {
      kept.push(slot)
    }
  }
  self.slots.clear()
  for slot in kept {
    self.slots.push(slot)
  }
  found
}

///|
/// Every registered slot, in the order they were added.
pub fn Hub::slots(self : Hub) -> Array[Slot] {
  self.slots
}

///|
/// How every slot stands.
pub fn Hub::status(self : Hub) -> Array[Status] {
  let out : Array[Status] = []
  for slot in self.slots {
    out.push(slot.status())
  }
  out
}

///|
/// The slot called `name`, if there is one.
fn Hub::slot(self : Hub, name : String) -> Slot? {
  for slot in self.slots {
    if slot.name() == name {
      return Some(slot)
    }
  }
  None
}

///|
/// A logger writing to this hub under `target`, which is usually a module path.
pub fn Hub::logger(self : Hub, target : String) -> Logger {
  Logger::new(self, target)
}

///|
/// Raises an incident through `on_fail`'s alarm, if it has one.
fn Hub::alarm(
  self : Hub,
  slot : Slot,
  fault : Fault?,
  phase : Phase,
  now : Int64,
) -> Unit {
  let alarm = match slot.policy() {
    Alarm(alarm) => alarm
    _ => return
  }
  let error = match fault {
    Some(fault) => fault.error
    None => ""
  }
  let incident = Incident::new(slot.name(), "sink", phase, error, now)
  incident.skipped = slot.status().skipped
  incident.dropped = slot.status().dropped
  incident.since = slot.status().since
  ignore(sound(alarm, incident, self))
}

///|
/// Sends `record` everywhere it belongs: through the global chain, then to each
/// slot's own filter and steps, then to its sink.
fn Hub::dispatch(self : Hub, record : Record) -> Unit {
  let now = self.now()
  if !self.filter.allows(record.level, record.target) {
    return
  }
  if !self.filter.admits(record.level, record.target, record.msg) {
    return
  }
  let env = Env::at(now)
  let refined = match run_chain(self.chain, record, env) {
    Some(refined) => refined
    None => return
  }
  let scene = self.scene()
  for slot in self.slots {
    if slot.alarm_only || !slot.wants(refined.level, refined.target) {
      continue
    }
    let kept = match slot.refine(refined, env) {
      Some(kept) => kept
      None => continue
    }
    let report = slot.send(kept, scene, now)
    match report.phase {
      Some(phase) => self.alarm(slot, report.fault, phase, now)
      None => ()
    }
  }
}

///|
/// Writes a record at `level` from `target`.
pub fn Hub::write(
  self : Hub,
  level : Level,
  target : String,
  msg : String,
  fields~ : Array[(String, Value)] = [],
) -> Unit {
  let now = self.now()
  let record = Record::of(level, target, msg)
    .sets(fields)
    .stamped(now)
    .numbered(self.seq)
  self.seq = self.seq + 1L
  self.dispatch(record)
}

///|
/// Writes what every queue holds, up to `now`.
pub fn Hub::flush(self : Hub) -> Unit {
  let now = self.now()
  let scene = self.scene()
  for slot in self.slots {
    ignore(slot.flush(scene, now).fault)
  }
}

///|
/// The hubs an alarm walk can see: every slot on the log route, and a way to
/// write to one of them without going through its filter or queue.
pub impl Desk for Hub with fn logs(self) {
  let names : Array[String] = []
  for slot in self.slots {
    if !slot.alarm_only {
      names.push(slot.name())
    }
  }
  names
}

///|
pub impl Desk for Hub with fn resting(self, name) {
  match self.slot(name) {
    Some(slot) => slot.resting(self.now())
    None => true
  }
}

///|
pub impl Desk for Hub with fn deliver(self, name, record) {
  match self.slot(name) {
    Some(slot) => {
      let now = self.now()
      let report = slot.deliver(record.stamped(now), self.scene(), now)
      match report.fault {
        Some(fault) => Err(fault.error)
        None => Ok(())
      }
    }
    None => Err("no sink called `" + name + "`")
  }
}

///|
pub extend Hub with Desk::{logs, resting, deliver}
