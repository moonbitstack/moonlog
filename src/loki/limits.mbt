// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How much a Loki sink holds while it waits for its next push, and how much
/// goes in one request.
///
/// `capacity` is a ceiling on entries waiting to be sent; when the queue is
/// full the oldest goes, because a shipper that stops the program it logs for
/// is worse than one that loses the start of an outage. `timeout` is in
/// seconds and applies to one request.
pub(all) struct Limits {
  capacity : Int32
  batch : Int32
  timeout : Int32
}

///|
/// Eight thousand entries, which is a few seconds of a busy service, and one
/// request's worth of them.
pub fn Limits::new(
  capacity~ : Int32 = 8_192,
  batch~ : Int32 = 512,
  timeout~ : Int32 = 10,
) -> Limits {
  { capacity, batch, timeout, }
}

///|
/// The same limits, holding a different number of entries.
pub fn Limits::capacity(self : Limits, capacity : Int32) -> Limits {
  { capacity, batch: self.batch, timeout: self.timeout, }
}

///|
/// The same limits, pushng a different number of entries at a time.
pub fn Limits::batch(self : Limits, batch : Int32) -> Limits {
  { capacity: self.capacity, batch, timeout: self.timeout, }
}

///|
/// The same limits, waiting a different number of seconds for an answer.
pub fn Limits::timeout(self : Limits, timeout : Int32) -> Limits {
  { capacity: self.capacity, batch: self.batch, timeout, }
}
