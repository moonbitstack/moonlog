// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A setting as a string. The parser has already checked that anything that is
/// there has the shape the key asks for, so a `None` here only means the
/// document left the key out.
pub fn Slot::text(self : Slot, key : String) -> String? {
  match self.settings.get(key) {
    Some(value) => as_text(value)
    None => None
  }
}

///|
/// A setting as a yes or no.
pub fn Slot::flag(self : Slot, key : String) -> Bool? {
  match self.settings.get(key) {
    Some(value) => as_flag(value)
    None => None
  }
}

///|
/// A setting as a whole number.
pub fn Slot::count(self : Slot, key : String) -> Int32? {
  match self.settings.get(key) {
    Some(value) =>
      match as_count(value) {
        Some(number) => Some(number.to_int())
        None => None
      }
    None => None
  }
}

///|
/// A setting as a byte count, `10mb` and a bare number alike.
pub fn Slot::size(self : Slot, key : String) -> Int64? {
  match self.settings.get(key) {
    Some(value) =>
      match as_count(value) {
        Some(number) => Some(number.to_int64())
        None =>
          match as_text(value) {
            Some(text) => Some(parse_size(key, text)) catch { _ => None }
            None => None
          }
      }
    None => None
  }
}

///|
/// A setting as a number of nanoseconds.
pub fn Slot::span(self : Slot, key : String) -> Int64? {
  match self.settings.get(key) {
    Some(value) =>
      match as_text(value) {
        Some(text) => Some(parse_span(key, text)) catch { _ => None }
        None => None
      }
    None => None
  }
}

///|
/// A setting as a list of strings.
pub fn Slot::texts(self : Slot, key : String) -> Array[String]? {
  match self.settings.get(key) {
    Some(value) =>
      match as_list(value) {
        Some(items) => {
          let out : Array[String] = []
          for item in items {
            match as_text(item) {
              Some(text) => out.push(text)
              None => return None
            }
          }
          Some(out)
        }
        None => None
      }
    None => None
  }
}

///|
/// A setting as a table of strings, in document order where the format keeps
/// one.
pub fn Slot::pairs(self : Slot, key : String) -> Array[(String, String)]? {
  match self.settings.get(key) {
    Some(value) =>
      match as_table(value) {
        Some(table) => {
          let out : Array[(String, String)] = []
          for name, item in table {
            match as_text(item) {
              Some(text) => out.push((name, text))
              None => return None
            }
          }
          Some(out)
        }
        None => None
      }
    None => None
  }
}

///|
/// The keys this slot's kind reads, which is what a deployment file is checked
/// against.
pub fn Slot::keys(self : Slot) -> Array[String] {
  let names : Array[String] = []
  for pair in kinds {
    if pair.0 == self.kind {
      for setting in pair.1 {
        names.push(setting.0)
      }
    }
  }
  names
}
