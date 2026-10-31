// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// When a file is rotated.
///
/// `size` is a limit in bytes and `every` a span in nanoseconds; zero turns
/// either one off. A file that has been written to rotates before the line that
/// would cross the limit, so a line never straddles two files.
pub(all) struct Rotation {
  size : Int64
  every : Int64
}

///|
/// No rotation: the file grows until something else deals with it.
pub fn Rotation::new(size~ : Int64 = 0L, every~ : Int64 = 0L) -> Rotation {
  { size, every, }
}

///|
/// The same rotation, with a size limit.
pub fn Rotation::size(self : Rotation, size : Int64) -> Rotation {
  { size, every: self.every, }
}

///|
/// The same rotation, with a time limit.
pub fn Rotation::every(self : Rotation, every : Int64) -> Rotation {
  { size: self.size, every, }
}

///|
/// What becomes of the files rotation leaves behind.
///
/// All three are ceilings: zero keeps everything. `max_age` and `max_total`
/// are only applied to segments, never to the file being written.
pub(all) struct Limits {
  keep : Int32
  max_age : Int64
  max_total : Int64
}

///|
/// Keep every segment, for ever.
pub fn Limits::new(
  keep~ : Int32 = 0,
  max_age~ : Int64 = 0L,
  max_total~ : Int64 = 0L,
) -> Limits {
  { keep, max_age, max_total, }
}

///|
/// The same limits, keeping at most `keep` segments.
pub fn Limits::keep(self : Limits, keep : Int32) -> Limits {
  { keep, max_age: self.max_age, max_total: self.max_total, }
}

///|
/// The same limits, dropping segments older than `max_age` nanoseconds.
pub fn Limits::max_age(self : Limits, max_age : Int64) -> Limits {
  { keep: self.keep, max_age, max_total: self.max_total, }
}

///|
/// The same limits, dropping the oldest segments until the rest fit in
/// `max_total` bytes.
pub fn Limits::max_total(self : Limits, max_total : Int64) -> Limits {
  { keep: self.keep, max_age: self.max_age, max_total, }
}
