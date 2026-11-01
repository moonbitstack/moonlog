// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink that says no a few times before it says yes, so a slot's retries can
/// be counted from the outside.
struct Stubborn {
  mut refusals : Int32
  taken : Array[String]
}

///|
fn stubborn(refusals : Int32) -> Stubborn {
  { refusals, taken: [], }
}

///|
impl @moonlog.Sink for Stubborn with fn write(self, entry) {
  if self.refusals > 0 {
    self.refusals = self.refusals - 1
    return Err("not yet")
  }
  self.taken.push(entry.line)
  Ok(())
}

///|
/// A queued slot tries a failed write three more times before it counts the
/// failure, which is the default every implementation of the specification
/// gives a queue. A direct slot does not: a write with nowhere to wait must not
/// hold the caller.
test "a queued slot retries three times, a direct one not at all" {
  let queued = stubborn(3)
  let hub = @moonlog.Hub::new()
  ignore(
    hub.add(
      @moonlog.Slot::new(queued, name="queued").queue(
        @moonlog.Queue::new(size=8).batch(100),
      ),
    ),
  )
  hub.logger("app").info("through the queue")
  // Removing the slot writes what its queue holds; the sink refuses three
  // times and takes it on the fourth.
  assert_eq(hub.remove("queued"), true)
  assert_eq(queued.taken.length(), 1)
  assert_true(queued.taken[0].has_suffix("through the queue"))
  let direct = stubborn(1)
  let hub = @moonlog.Hub::new()
  ignore(hub.add(@moonlog.Slot::new(direct, name="direct")))
  hub.logger("app").info("straight through")
  assert_eq(direct.taken.length(), 0)
  assert_eq(hub.status()[0].health.name(), "down")
}

///|
/// A slot told how many retries it gets keeps that number, whatever its queue.
test "a slot told its retries keeps them" {
  let sink = stubborn(2)
  let hub = @moonlog.Hub::new()
  ignore(
    hub.add(
      @moonlog.Slot::new(sink, name="asked")
      .queue(@moonlog.Queue::new(size=8).batch(100))
      .retries(1),
    ),
  )
  hub.logger("app").info("one try is all it gets")
  ignore(hub.remove("asked"))
  // One retry means two attempts, and the sink refuses both: had the slot kept
  // the default of three, the third attempt would have gone through.
  assert_eq(sink.taken.length(), 0)
  assert_eq(sink.refusals, 0)
}
