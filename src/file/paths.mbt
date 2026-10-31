// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// `dir/name` split apart, with the directory `.` when there is no separator
/// and the separator kept when the path is a root (`/x`, `C:\x`).
fn split_path(path : String) -> (String, String) {
  let chars = path.to_array()
  let mut cut = -1
  for i in 0..<chars.length() {
    if chars[i] == '/' || chars[i] == '\\' {
      cut = i
    }
  }
  if cut < 0 {
    return (".", path)
  }
  let name = path[cut + 1:].to_owned()
  let mut dir = path[:cut].to_owned()
  if dir.length() == 2 && dir[1] == ':' {
    // `C:\app.log`: the drive is the whole directory, separator included.
    dir = path[:cut + 1].to_owned()
  } else if dir.length() == 0 {
    dir = path[:1].to_owned()
  }
  (dir, name)
}

///|
/// `20261101T090000`: the instant a segment was cut, in UTC, so names sort.
fn stamp(at : Int64) -> String {
  let out = StringBuilder()
  @moonlog.Clock::Custom("%Y%m%dT%H%M%S").write(out, at, 0)
  out.to_string()
}

///|
/// The number at the end of a three-digit sequence, or 0 for anything else.
fn number_of(digits : String) -> Int32 {
  let mut n = 0
  for c in digits {
    if c < '0' || c > '9' {
      return 0
    }
    n = n * 10 + (c.to_int() - 48)
  }
  n
}

///|
/// `001`, so that the names of one second still sort as the order they were
/// cut in.
fn pad3(n : Int32) -> String {
  let text = n.to_string()
  if text.length() >= 3 {
    text
  } else {
    "000"[:3 - text.length()].to_owned() + text
  }
}

///|
/// The name a segment cut at `at` is given: the file's own name and the
/// instant, with a sequence when two cuts land in the same second.
///
/// `names` are the entries already in the directory. The sequence continues
/// past the highest one there, never reusing a number a pruned segment once
/// had, because a name that sorts before the segment it belongs to would make
/// the history read backwards.
fn segment(base : String, names : Array[String]) -> String {
  let prefix = base + "-"
  let mut taken = false
  let mut highest = 0
  for name in names {
    if name == base || name == base + ".gz" {
      taken = true
    } else if name.has_prefix(prefix) {
      taken = true
      let rest = name[prefix.length():].to_owned()
      let digits = match rest.rev_find(".gz") {
        Some(cut) => rest[:cut].to_owned()
        None => rest
      }
      let n = number_of(digits)
      if n > highest {
        highest = n
      }
    }
  }
  if !taken {
    base
  } else {
    prefix + pad3(highest + 1)
  }
}
