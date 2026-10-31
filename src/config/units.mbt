// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A number and the unit written after it.
fn split_number(text : StringView) -> (StringView, StringView) {
  let chars = text.to_array()
  let mut at = 0
  let mut seen_dot = false
  while at < chars.length() {
    let c = chars[at]
    if c >= '0' && c <= '9' {
      at = at + 1
    } else if c == '.' && !seen_dot {
      seen_dot = true
      at = at + 1
    } else {
      break
    }
  }
  (text[:at], text[at:])
}

///|
/// A decimal written as an integer and the number of digits after the point,
/// so a size is never rounded by a float on the way.
fn decimal(at : String, text : StringView) -> (Int64, Int32) raise Refused {
  if text.length() == 0 {
    raise refuse(at, "nothing", "a number")
  }
  let mut value = 0L
  let mut scale = 0
  let mut after = false
  for c in text {
    if c == '.' {
      after = true
      continue
    }
    if c < '0' || c > '9' {
      raise refuse(at, text.to_owned(), "a number")
    }
    value = value * 10L + (c.to_int() - 48).to_int64()
    if after {
      scale = scale + 1
    }
  }
  if scale > 6 {
    raise refuse(at, text.to_owned(), "no more than six digits after the point")
  }
  (value, scale)
}

///|
/// `value` scaled by `unit`, with the fractional digits applied by integer
/// arithmetic.
fn scaled(value : Int64, scale : Int32, unit : Int64) -> Int64 {
  let mut divisor = 1L
  for _ in 0..<scale {
    divisor = divisor * 10L
  }
  value * unit / divisor
}

///|
/// How many bytes a size names: `512`, `4kb`, `10MiB`, `1.5gb`.
///
/// A bare number is bytes. `k`, `m`, `g` and `t` are powers of a thousand,
/// `ki`, `mi`, `gi` and `ti` powers of 1024, with or without a `b`.
pub fn parse_size(at : String, text : StringView) -> Int64 raise Refused {
  let (number, unit) = split_number(text)
  let (value, scale) = decimal(at, number)
  let factor = match unit.to_lower() {
    "" | "b" => 1L
    "k" | "kb" => 1_000L
    "ki" | "kib" => 1_024L
    "m" | "mb" => 1_000_000L
    "mi" | "mib" => 1_048_576L
    "g" | "gb" => 1_000_000_000L
    "gi" | "gib" => 1_073_741_824L
    "t" | "tb" => 1_000_000_000_000L
    "ti" | "tib" => 1_099_511_627_776L
    _ => raise refuse(at, text.to_owned(), "a size such as 10mb or 1GiB")
  }
  scaled(value, scale, factor)
}

///|
/// How many nanoseconds a span names: `200ms`, `5s`, `1m30s`, `2h`.
///
/// A span always says its unit — a bare number is refused, because a
/// configuration that means seconds in one program and nanoseconds in another
/// is a configuration that is wrong silently.
pub fn parse_span(at : String, text : StringView) -> Int64 raise Refused {
  if text.length() == 0 {
    raise refuse(at, "nothing", "a span such as 5s")
  }
  let mut total = 0L
  let mut rest = text
  let mut parts = 0
  while rest.length() > 0 {
    let (number, after) = split_number(rest)
    if number.length() == 0 {
      raise refuse(at, text.to_owned(), "a span such as 5s")
    }
    let (value, scale) = decimal(at, number)
    let chars = after.to_array()
    let mut unit_at = 0
    while unit_at < chars.length() {
      let c = chars[unit_at]
      if c >= '0' && c <= '9' {
        break
      }
      unit_at = unit_at + 1
    }
    let unit = after[:unit_at].to_lower()
    let factor = match unit {
      "ns" => 1L
      "us" => 1_000L
      "ms" => 1_000_000L
      "s" => 1_000_000_000L
      "m" => 60_000_000_000L
      "h" => 3_600_000_000_000L
      "d" => 86_400_000_000_000L
      "w" => 604_800_000_000_000L
      _ =>
        raise refuse(at, text.to_owned(), "a span such as 5s, 200ms or 1m30s")
    }
    total = total + scaled(value, scale, factor)
    parts = parts + 1
    rest = after[unit_at:]
  }
  if parts == 0 {
    raise refuse(at, text.to_owned(), "a span such as 5s")
  }
  total
}
