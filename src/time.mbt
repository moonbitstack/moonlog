// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How an instant is written.
///
/// The library holds no clock, so every instant here arrives as nanoseconds
/// since the epoch and every local time is the instant shifted by an offset
/// that was handed in. `Custom` is a strftime spec, `Go` a reference-time
/// layout and `Ldml` a Unicode date pattern, each with everything moondate reads
/// in that style.
pub(all) enum Clock {
  Local
  Utc
  Rfc3339
  Iso
  Unix
  UnixMs
  UnixNs
  Custom(String)
  Go(String)
  Ldml(String)
} derive(Eq, Debug)

///|
pub extend Clock with Debug::{to_repr}

///|
pub extend Clock with Eq::{equal, not_equal}

///|
/// A clock spec, as a `{time:…}` hole spells it. A spec that is none of the names
/// is strftime, unless `go:` or `ldml:` says otherwise.
pub fn Clock::parse(spec : StringView) -> Clock {
  match spec {
    "" | "local" => Local
    "utc" => Utc
    "rfc3339" => Rfc3339
    "iso" => Iso
    "unix" => Unix
    "unix_ms" => UnixMs
    "unix_ns" => UnixNs
    [.. "go:", .. layout] => Go(layout.to_owned())
    [.. "ldml:", .. pattern] => Ldml(pattern.to_owned())
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
    Local =>
      out.write_string(
        moment(time, offset).isoformat(sep=' ', fraction=3, offset=false),
      )
    Utc => out.write_string(instant(time).isoformat(fraction=0))
    Rfc3339 => out.write_string(moment(time, offset).isoformat(fraction=6))
    Iso => write_iso(out, time)
    Unix => out.write_string(floor_div(time, 1_000_000_000L).to_string())
    UnixMs => out.write_string(floor_div(time, 1_000_000L).to_string())
    UnixNs => out.write_string(time.to_string())
    Custom(spec) => write_strftime(out, time, offset, spec)
    Go(layout) => out.write_string(moment(time, offset).layout(layout))
    Ldml(pattern) => out.write_string(moment(time, offset).pattern(pattern))
  }
}

///|
/// The instant at `offset` seconds east of UTC. moondate's offsets are whole minutes, as every
/// zone in use today is.
fn moment(time : Int64, offset : Int32) -> @moondate.Moment {
  let seconds = floor_div(time, 1_000_000_000L)
  @moondate.Moment::of_epoch(
    seconds,
    nano=(time - seconds * 1_000_000_000L).to_int(),
    zone=Offset(offset / 60),
  )
}

///|
/// The instant in UTC, which writes as `Z`.
fn instant(time : Int64) -> @moondate.Moment {
  let seconds = floor_div(time, 1_000_000_000L)
  @moondate.Moment::of_epoch(
    seconds,
    nano=(time - seconds * 1_000_000_000L).to_int(),
  )
}

///|
/// `2023-11-14T22:13:20.000Z`: milliseconds, which is what JSON schemas want.
fn write_iso(out : StringBuilder, time : Int64) -> Unit {
  out.write_string(instant(time).isoformat(fraction=3))
}

///|
/// `2023-11-14T22:13:20.000000000Z`: nanoseconds, as the OpenTelemetry model
/// writes a timestamp.
fn write_iso_nanos(out : StringBuilder, time : Int64) -> Unit {
  out.write_string(instant(time).isoformat(fraction=9))
}

///|
/// A strftime spec, at `offset` seconds east of UTC.
fn write_strftime(
  out : StringBuilder,
  time : Int64,
  offset : Int32,
  spec : String,
) -> Unit {
  out.write_string(moment(time, offset).strftime(spec))
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
