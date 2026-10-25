// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How severe a record is.
///
/// A level is a value rather than an enumeration so an application can define
/// its own — `Level::{ name: "notice", value: 35, colour: Blue }` — and have it
/// work in filters, calls and layouts alike. Only `value` counts when levels are
/// compared; `name` is what filters and labels read.
pub(all) struct Level {
  name : String
  value : Int32
  colour : Colour
}

///|
/// Step-by-step detail.
pub let trace : Level = { name: "trace", value: 10, colour: Colour::Cyan, }

///|
/// Diagnostics for developers.
pub let debug : Level = { name: "debug", value: 20, colour: Colour::Magenta, }

///|
/// Normal operation.
pub let info : Level = { name: "info", value: 30, colour: Colour::Green, }

///|
/// Something unexpected that the program survived.
pub let warn : Level = { name: "warn", value: 40, colour: Colour::Yellow, }

///|
/// A failure that needs attention.
pub let error : Level = { name: "error", value: 50, colour: Colour::Red, }

///|
/// A failure the program cannot carry on from.
pub let fatal : Level = { name: "fatal", value: 60, colour: Colour::Alarm, }

///|
/// The six built-in levels, quietest first.
pub fn built_in() -> Array[Level] {
  [trace, debug, info, warn, error, fatal]
}

///|
/// Its number.
pub fn Level::value(self : Level) -> Int32 {
  self.value
}

///|
/// Its lower-case name, as filters, labels and configuration files write it.
pub fn Level::name(self : Level) -> String {
  self.name
}

///|
/// Its colour in a terminal.
pub fn Level::colour(self : Level) -> Colour {
  self.colour
}

///|
/// The same level under another name, which is how a profile's vocabulary
/// reaches a JSON document.
pub fn Level::named(self : Level, name : String) -> Level {
  { name, value: self.value, colour: self.colour, }
}

///|
/// Whether this level passes a minimum.
pub fn Level::at_least(self : Level, min : Level) -> Bool {
  self.value >= min.value
}

///|
/// A level by name or by number, in any capitalisation.
///
/// `warning` is `warn`, `critical` is `fatal`, and `0` to `255` is a level by
/// value, so a level defined by an application is still spelled the same way
/// once it reaches a filter.
pub fn Level::parse(name : StringView) -> Level raise Refused {
  let s = name.to_lower()
  match s {
    "trace" => trace
    "debug" => debug
    "info" => info
    "warn" | "warning" => warn
    "error" | "err" => error
    "fatal" | "critical" => fatal
    _ =>
      match number(s) {
        Some(n) if n >= 0 && n <= 255 =>
          { name: s.to_owned(), value: n, colour: Colour::Plain, }
        _ =>
          raise refuse(
            0,
            name.to_owned(),
            "trace, debug, info, warn, error, fatal or 0 to 255",
          )
      }
  }
}

///|
/// A decimal number, or `None` when `s` holds anything else.
fn number(s : StringView) -> Int32? {
  if s.length() == 0 {
    return None
  }
  let mut n = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - 48)
  }
  Some(n)
}

///|
/// How a profile's logger writes this level.
///
/// A pattern preset uses its own logger's vocabulary; every other layout uses
/// the profile in force. Python's `WARNING` and `CRITICAL`, and `slog`'s
/// numeric names for the two levels it has no word for, are the only
/// differences — which is the point of a profile.
pub fn Level::label(self : Level, profile : Profile) -> String {
  match self.value {
    40 => if profile == Profile::Python { "WARNING" } else { "WARN" }
    60 =>
      if profile == Profile::Python {
        "CRITICAL"
      } else if profile == Profile::Slog {
        "ERROR+4"
      } else {
        "FATAL"
      }
    10 => if profile == Profile::Slog { "DEBUG-4" } else { "TRACE" }
    20 => "DEBUG"
    30 => "INFO"
    50 => "ERROR"
    _ => self.name.to_upper()
  }
}

///|
/// The syslog severity, for GELF and anything else shaped like syslog.
pub fn Level::syslog(self : Level) -> Int32 {
  if self.value <= 20 {
    7
  } else if self.value <= 30 {
    6
  } else if self.value <= 40 {
    4
  } else if self.value <= 50 {
    3
  } else {
    2
  }
}

///|
/// The number Logstash writes, 5000 to 40000.
pub fn Level::logstash(self : Level) -> Int32 {
  if self.value <= 10 {
    5000
  } else if self.value <= 20 {
    10000
  } else if self.value <= 30 {
    20000
  } else if self.value <= 40 {
    30000
  } else {
    40000
  }
}

///|
/// The severity number of the OpenTelemetry log model.
pub fn Level::otel(self : Level) -> Int32 {
  if self.value <= 10 {
    1
  } else if self.value <= 20 {
    5
  } else if self.value <= 30 {
    9
  } else if self.value <= 40 {
    13
  } else if self.value <= 50 {
    17
  } else {
    21
  }
}

///|
pub impl Eq for Level with fn equal(self, other) {
  self.value == other.value
}

///|
pub extend Level with Eq::{equal, not_equal}

///|
pub impl Compare for Level with fn compare(self, other) {
  if self.value < other.value {
    -1
  } else if self.value > other.value {
    1
  } else {
    0
  }
}

///|
pub extend Level with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
pub impl Show for Level with fn output(self, logger) {
  logger.write_string(self.name)
}

///|
pub extend Level with Show::{output, to_string}
