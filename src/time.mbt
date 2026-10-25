// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How an instant is written.
///
/// The library holds no clock, so every instant here arrives as nanoseconds
/// since the epoch and every local time is the instant shifted by an offset
/// that was handed in. A `Custom` spec is strftime, the subset below.
pub(all) enum Clock {
  Local
  Utc
  Rfc3339
  Unix
  UnixMs
  UnixNs
  Custom(String)
} derive(Eq, Debug)

///|
pub extend Clock with Debug::{to_repr}

///|
pub extend Clock with Eq::{equal, not_equal}

///|
/// A clock spec, as a `{time:…}` hole spells it.
pub fn Clock::parse(spec : StringView) -> Clock {
  match spec {
    "" | "local" => Local
    "utc" => Utc
    "rfc3339" => Rfc3339
    "unix" => Unix
    "unix_ms" => UnixMs
    "unix_ns" => UnixNs
    _ => Custom(spec.to_owned())
  }
}

///|
/// Writes `time` in this clock's form; `offset` is seconds east of UTC.
pub fn Clock::write(
  self : Clock,
  out : StringBuilder,
  time : Int64,
  offset : Int32,
) -> Unit {
  match self {
    Local => write_stamp(out, time, offset, 3)
    Utc => write_utc(out, time)
    Rfc3339 => write_offset_stamp(out, time, offset, 6, sep="T")
    Unix => out.write_string(floor_div(time, 1_000_000_000L).to_string())
    UnixMs => out.write_string(floor_div(time, 1_000_000L).to_string())
    UnixNs => out.write_string(time.to_string())
    Custom(spec) => write_strftime(out, time, offset, spec)
  }
}

///|
/// `2023-11-14 23:13:20.000`: what a default line puts in front.
fn write_stamp(
  out : StringBuilder,
  time : Int64,
  offset : Int32,
  digits : Int32,
) -> Unit {
  write_parts(out, time, offset, digits, sep=" ", zone=false)
}

///|
/// `2023-11-14T22:13:20Z`: whole seconds in UTC, as `{time:utc}` writes.
fn write_utc(out : StringBuilder, time : Int64) -> Unit {
  write_parts(out, time, 0, 0, sep="T", zone=false)
  out.write_char('Z')
}

///|
/// `2023-11-14T22:13:20.000Z`: milliseconds, which is what JSON schemas want.
fn write_iso(out : StringBuilder, time : Int64) -> Unit {
  write_parts(out, time, 0, 3, sep="T", zone=false)
  out.write_char('Z')
}

///|
/// `2023-11-14T22:13:20.000000000Z`: nanoseconds, as the OpenTelemetry model
/// writes a timestamp.
fn write_iso_nanos(out : StringBuilder, time : Int64) -> Unit {
  write_parts(out, time, 0, 9, sep="T", zone=false)
  out.write_char('Z')
}

///|
/// `2023-11-14T23:13:20.000000+01:00`: local time with its offset.
fn write_offset_stamp(
  out : StringBuilder,
  time : Int64,
  offset : Int32,
  digits : Int32,
  sep~ : String = "T",
) -> Unit {
  write_parts(out, time, offset, digits, sep~, zone=true)
}

///|
/// The date and time at `offset`, optionally followed by the offset itself.
fn write_parts(
  out : StringBuilder,
  time : Int64,
  offset : Int32,
  digits : Int32,
  sep~ : String,
  zone~ : Bool,
) -> Unit {
  let shifted = time + offset.to_int64() * 1_000_000_000L
  let (year, month, day, hour, minute, second, nanos) = broken_down(shifted)
  write_digits(out, year, 4)
  out.write_char('-')
  write_digits(out, month, 2)
  out.write_char('-')
  write_digits(out, day, 2)
  out.write_string(sep)
  write_digits(out, hour, 2)
  out.write_char(':')
  write_digits(out, minute, 2)
  out.write_char(':')
  write_digits(out, second, 2)
  if digits > 0 {
    let scale = pow10(9 - digits)
    let frac = nanos / scale.to_int64()
    out.write_char('.')
    write_digits(out, frac.to_int(), digits)
  }
  if zone {
    write_zone(out, offset)
  }
}

///|
/// `+01:00`, or `+0000` when a strftime `%z` asks for the compact form.
fn write_zone(out : StringBuilder, offset : Int32) -> Unit {
  let sign = if offset < 0 { '-' } else { '+' }
  let abs = if offset < 0 { -offset } else { offset }
  let hours = abs / 3600
  let minutes = abs / 60 % 60
  out.write_char(sign)
  write_digits(out, hours, 2)
  out.write_char(':')
  write_digits(out, minutes, 2)
}

///|
/// Writes `n` with at least `width` digits, zero-padded.
fn write_digits(out : StringBuilder, n : Int32, width : Int32) -> Unit {
  let text = n.to_string()
  let mut pad = width - text.length()
  while pad > 0 {
    out.write_char('0')
    pad = pad - 1
  }
  out.write_string(text)
}

///|
/// The instant split into civil parts, UTC.
fn broken_down(
  time : Int64,
) -> (Int32, Int32, Int32, Int32, Int32, Int32, Int64) {
  let day = floor_div(time, 86_400_000_000_000L)
  let rest = time - day * 86_400_000_000_000L
  let (year, month, date) = civil_from_days(day.to_int())
  let hour = (rest / 3_600_000_000_000L).to_int()
  let minute = (rest / 60_000_000_000L % 60L).to_int()
  let second = (rest / 1_000_000_000L % 60L).to_int()
  let nanos = rest % 1_000_000_000L
  (year, month, date, hour, minute, second, nanos)
}

///|
/// Days since the epoch to a civil date, by Hinnant's `civil_from_days`.
fn civil_from_days(days : Int32) -> (Int32, Int32, Int32) {
  let z = days + 719468
  let era = if z >= 0 { z / 146097 } else { (z - 146096) / 146097 }
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if m <= 2 { y + 1 } else { y }
  (year, m, d)
}

///|
/// Division that rounds towards negative infinity, so instants before 1970
/// land on the day they belong to.
fn floor_div(a : Int64, b : Int64) -> Int64 {
  let q = a / b
  if a % b != 0L && (a < 0L) != (b < 0L) {
    q - 1L
  } else {
    q
  }
}

///|
fn pow10(n : Int32) -> Int32 {
  let mut out = 1
  for _ in 0..<n {
    out = out * 10
  }
  out
}

///|
/// strftime, the subset the layouts use: `%Y %m %d %H %M %S %f %z %:z %%`, and
/// `%.Nf` for N fractional digits.
fn write_strftime(
  out : StringBuilder,
  time : Int64,
  offset : Int32,
  spec : String,
) -> Unit {
  let shifted = time + offset.to_int64() * 1_000_000_000L
  let (year, month, day, hour, minute, second, nanos) = broken_down(shifted)
  let chars = spec.to_array()
  let mut i = 0
  while i < chars.length() {
    let c = chars[i]
    if c != '%' {
      out.write_char(c)
      i = i + 1
      continue
    }
    i = i + 1
    if i >= chars.length() {
      out.write_char('%')
      break
    }
    let mut digits = -1
    if chars[i] == '.' {
      i = i + 1
      let mut n = 0
      while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
        n = n * 10 + (chars[i].to_int() - 48)
        i = i + 1
      }
      digits = n
    }
    let mut colon = false
    if i < chars.length() && chars[i] == ':' {
      colon = true
      i = i + 1
    }
    if i >= chars.length() {
      out.write_char('%')
      break
    }
    match chars[i] {
      'Y' => write_digits(out, year, 4)
      'm' => write_digits(out, month, 2)
      'd' => write_digits(out, day, 2)
      'e' => write_digits(out, day, 2)
      'H' => write_digits(out, hour, 2)
      'M' => write_digits(out, minute, 2)
      'S' => write_digits(out, second, 2)
      'f' => {
        let n = if digits >= 0 { digits } else { 9 }
        let scale = pow10(9 - n)
        out.write_char('.')
        write_digits(out, (nanos / scale.to_int64()).to_int(), n)
      }
      'z' =>
        if colon {
          write_zone(out, offset)
        } else {
          let sign = if offset < 0 { '-' } else { '+' }
          let abs = if offset < 0 { -offset } else { offset }
          out.write_char(sign)
          write_digits(out, abs / 3600, 2)
          write_digits(out, abs / 60 % 60, 2)
        }
      '%' => out.write_char('%')
      other => {
        out.write_char('%')
        out.write_char(other)
      }
    }
    i = i + 1
  }
}
