// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How a record becomes one line.
///
/// A layout knows nothing about where the line goes; a sink is handed the line
/// its slot's layout made of the record.
pub(open) trait Layout {
  fn render(Self, Record, Scene) -> String
}

///|
pub impl Layout for Pattern with fn render(self, record, scene) {
  self.render_line(record, scene)
}

///|
pub extend Pattern with Layout::{render}

///|
/// One `key=value` line per record: `time=… level=… target=… msg=… key=value`.
///
/// Values are quoted the logfmt way, so a message with a space in it cannot be
/// mistaken for two fields. This is the shape a shell pipeline reads with
/// `cut` and `awk`.
pub struct Logfmt {}

///|
pub fn Logfmt::new() -> Logfmt {
  Logfmt::{ }
}

///|
pub impl Layout for Logfmt with fn render(_self, record, scene) {
  let out = StringBuilder()
  out.write_string("time=")
  Clock::Utc.write(out, record.time, 0)
  out.write_string(" level=")
  out.write_string(record.level.name())
  out.write_string(" target=")
  write_logfmt(out, record.target)
  out.write_string(" msg=")
  write_logfmt(out, record.msg)
  write_fields(out, record, true, false)
  let _ = scene
  out.to_string()
}

///|
pub extend Logfmt with Layout::{render}

///|
/// A first line with the time, level, target and message, then one aligned
/// `key = value` line per field. What a person reads in a terminal when the
/// fields matter more than the bytes.
pub struct Pretty {}

///|
pub fn Pretty::new() -> Pretty {
  Pretty::{ }
}

///|
pub impl Layout for Pretty with fn render(_self, record, scene) {
  let out = StringBuilder()
  let clock = StringBuilder()
  Clock::Local.write(clock, record.time, (scene.identity.offset)(record.time))
  paint(out, scene.colour, Colour::Grey, clock.to_string())
  out.write_char(' ')
  paint(
    out,
    scene.colour,
    record.level.colour,
    pad(record.level.label(scene.profile), 5, '<'),
  )
  out.write_char(' ')
  paint(out, scene.colour, Colour::White, record.target)
  out.write_char(' ')
  out.write_string(record.msg)
  let rows : Array[(String, String)] = []
  for pair in record.fields {
    flat_rows(rows, pair.0, pair.1)
  }
  let mut width = 0
  for (key, _) in rows {
    if key.char_length() > width {
      width = key.char_length()
    }
  }
  for (key, value) in rows {
    out.write_string("\n    ")
    paint(out, scene.colour, Colour::Cyan, pad(key, width, '<'))
    out.write_string(" = ")
    out.write_string(value)
  }
  out.to_string()
}

///|
fn flat_rows(
  rows : Array[(String, String)],
  key : String,
  value : Value,
) -> Unit {
  match value {
    Map(pairs) =>
      for (k, v) in pairs {
        flat_rows(rows, key + "." + k, v)
      }
    _ => rows.push((key, value.to_text()))
  }
}

///|
pub extend Pretty with Layout::{render}

///|
/// Wraps `text` in `colour` when the scene takes colour.
fn paint(
  out : StringBuilder,
  on : Bool,
  colour : Colour,
  text : String,
) -> Unit {
  if on && colour != Colour::Plain {
    out.write_string(colour.ansi())
    out.write_string(text)
    out.write_string(reset)
  } else {
    out.write_string(text)
  }
}
