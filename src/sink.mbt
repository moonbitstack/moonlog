// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a sink is handed: the record, and the line its slot's layout made of
/// it. The line is made once, whether or not the sink reads it.
pub(all) struct Entry {
  record : Record
  line : String
}

///|
/// Where entries go.
///
/// Only `write` is required. Queues, retries, health and alarms belong to the
/// slot the sink is registered in, so a sink delivers and says what went wrong
/// and nothing more. `Err` is a failure worth telling someone about; a sink that
/// cannot fail answers `Ok`.
pub(open) trait Sink {
  /// Writes one entry; `Err` says why it could not.
  fn write(Self, Entry) -> Result[Unit, String]
}

///|
/// A sink that writes each line through a function.
///
/// This is the seam: `Lines::new(fn(line) { println(line) })` prints, and
/// `Lines::new(fn(line) { held.push(line) })` is how a test reads what was
/// written without a terminal in the way.
pub struct Lines {
  write : (String) -> Unit
}

///|
/// A sink that hands each line to `write`.
pub fn Lines::new(write : (String) -> Unit) -> Lines {
  { write, }
}

///|
pub impl Sink for Lines with fn write(self, entry) {
  (self.write)(entry.line)
  Ok(())
}

///|
pub extend Lines with Sink::{write}

///|
/// A sink that drops everything, for an application that configures logging off
/// and a test that would rather not have output.
pub struct Discard {}

///|
/// A sink that accepts every entry and keeps none.
pub fn Discard::new() -> Discard {
  Discard::{ }
}

///|
pub impl Sink for Discard with fn write(_self, _entry) {
  Ok(())
}

///|
pub extend Discard with Sink::{write}

///|
/// A sink that keeps the newest entries in memory, for a test or a status page.
pub struct Memory {
  size : Int32
  entries : Array[Entry]
}

///|
/// Keeps the newest `size` entries; 0 keeps everything.
pub fn Memory::new(size~ : Int32 = 0) -> Memory {
  { size, entries: [], }
}

///|
pub impl Sink for Memory with fn write(self, entry) {
  self.entries.push(entry)
  if self.size > 0 && self.entries.length() > self.size {
    let kept : Array[Entry] = []
    let from = self.entries.length() - self.size
    for i in from..<self.entries.length() {
      kept.push(self.entries[i])
    }
    self.entries.clear()
    for entry in kept {
      self.entries.push(entry)
    }
  }
  Ok(())
}

///|
pub extend Memory with Sink::{write}

///|
/// The records it kept, oldest first.
pub fn Memory::records(self : Memory) -> Array[Record] {
  let out : Array[Record] = []
  for entry in self.entries {
    out.push(entry.record)
  }
  out
}

///|
/// The lines it kept, oldest first.
pub fn Memory::lines(self : Memory) -> Array[String] {
  let out : Array[String] = []
  for entry in self.entries {
    out.push(entry.line)
  }
  out
}

///|
/// The entries whose line contains `text`.
pub fn Memory::find(self : Memory, text : String) -> Array[Entry] {
  let out : Array[Entry] = []
  for entry in self.entries {
    if entry.line.contains(text) {
      out.push(entry)
    }
  }
  out
}

///|
/// Forgets everything it kept.
pub fn Memory::clear(self : Memory) -> Unit {
  self.entries.clear()
}
