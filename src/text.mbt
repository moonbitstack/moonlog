// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The preset whose pattern is `text`, when `text` is a preset name.
fn preset_of(text : StringView) -> Profile? {
  match text {
    "serlog" => Some(Profile::Serlog)
    "tracing" => Some(Profile::Tracing)
    "env_logger" => Some(Profile::EnvLogger)
    "python" => Some(Profile::Python)
    "logback" | "log4j" => Some(Profile::Logback)
    "slog" => Some(Profile::Slog)
    "pino" => Some(Profile::Pino)
    _ => None
  }
}

///|
/// ` key=value` for every field, groups spread as `group.key`; `error` is left
/// out when the pattern shows it in its own hole.
fn write_fields(
  out : StringBuilder,
  record : Record,
  quoted : Bool,
  skip_error : Bool,
) -> Unit {
  for pair in record.fields {
    write_flat(out, pair.0, pair.1, quoted, skip_error)
  }
}

///|
fn write_flat(
  out : StringBuilder,
  key : String,
  value : Value,
  quoted : Bool,
  skip_error : Bool,
) -> Unit {
  if skip_error && key == "error" {
    return
  }
  match value {
    Map(pairs) =>
      for (k, v) in pairs {
        write_flat(out, key + "." + k, v, quoted, skip_error)
      }
    _ => {
      out.write_char(' ')
      out.write_string(key)
      out.write_char('=')
      if quoted {
        write_logfmt(out, value.to_text())
      } else {
        out.write_string(value.to_text())
      }
    }
  }
}

///|
/// Shortens the leading segments of a target to their first letter until it
/// fits `width`.
fn shorten(target : StringView, width : Int32) -> String {
  if target.char_length() <= width {
    return target.to_owned()
  }
  let sep = if target.contains(("::" : StringView)) { "::" } else { "." }
  let parts = target.split(sep)
  let out : Array[String] = []
  for part in parts {
    out.push(part.to_owned())
  }
  let mut i = 0
  while i + 1 < out.length() && joined_length(out, sep) > width {
    let chars = out[i].to_array()
    out[i] = if chars.length() > 0 { chars[0].to_string() } else { "" }
    i = i + 1
  }
  join(out, sep)
}

///|
fn joined_length(parts : Array[String], sep : String) -> Int32 {
  let mut total = 0
  for i, part in parts {
    if i > 0 {
      total = total + sep.length()
    }
    total = total + part.char_length()
  }
  total
}

///|
fn join(parts : Array[String], sep : String) -> String {
  let out = StringBuilder()
  for i, part in parts {
    if i > 0 {
      out.write_string(sep)
    }
    out.write_string(part)
  }
  out.to_string()
}

///|
/// A run of characters as a string.
fn chars_to_string(chars : ArrayView[Char]) -> String {
  let out = StringBuilder()
  for c in chars {
    out.write_char(c)
  }
  out.to_string()
}

///|
/// The last segment of a path, whichever separator the platform writes.
fn base_name(path : StringView) -> String {
  let chars = path.to_array()
  let mut start = 0
  for i, c in chars {
    if c == '/' || c == '\\' {
      start = i + 1
    }
  }
  chars_to_string(chars[start:])
}

///|
/// Milliseconds from the identity's start to the record's instant.
fn elapsed_ms(record : Record, identity : Identity) -> Int64 {
  if identity.start == 0L {
    return 0L
  }
  floor_div(record.time - identity.start, 1_000_000L)
}
