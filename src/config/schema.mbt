// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A string, or nothing.
fn as_text(value : Json) -> String? {
  match value {
    String(text) => Some(text)
    _ => None
  }
}

///|
/// A boolean, or nothing.
fn as_flag(value : Json) -> Bool? {
  match value {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
/// A number, or nothing.
fn as_count(value : Json) -> Double? {
  match value {
    Number(number, ..) => Some(number)
    _ => None
  }
}

///|
/// A list, or nothing.
fn as_list(value : Json) -> Array[Json]? {
  match value {
    Array(items) => Some(items)
    _ => None
  }
}

///|
/// A table, or nothing.
fn as_table(value : Json) -> Map[String, Json]? {
  match value {
    Object(entries) => Some(entries)
    _ => None
  }
}

///|
/// What a setting holds, which is what makes an unknown or mistyped key a
/// refusal at the point it is read rather than a surprise at the point it is
/// used.
priv enum Setting {
  Text
  Flag
  Count
  Size
  Span
  Texts
  Pairs
}

///|
/// The settings the shipped sinks read, by kind. A name that is not here and
/// not one of the keys every slot has is refused with its path, so a typo in a
/// deployment file is caught before the process starts serving.
let kinds : Array[(String, Array[(String, Setting)])] = [
  ("stdio", [("stream", Setting::Text)]),
  (
    "file",
    [
      ("path", Text),
      ("append", Flag),
      ("perms", Count),
      ("mkdir", Flag),
      ("max_size", Size),
      ("every", Span),
      ("keep", Count),
      ("max_age", Span),
      ("max_total", Size),
      ("compress", Flag),
      ("buffer", Size),
    ],
  ),
  (
    "loki",
    [
      ("url", Text),
      ("tenant", Text),
      ("labels", Pairs),
      ("username", Text),
      ("password", Text),
      ("timeout", Span),
      ("capacity", Count),
      ("batch", Count),
    ],
  ),
  (
    "mail",
    [
      ("host", Text),
      ("port", Count),
      ("from", Text),
      ("to", Texts),
      ("subject", Text),
      ("level", Text),
      ("window", Span),
      ("at_most", Count),
      ("username", Text),
      ("password", Text),
      ("security", Text),
      ("subject_template", Text),
    ],
  ),
  ("memory", [("size", Count)]),
  ("discard", []),
]

///|
/// The settings every slot reads, whatever its kind.
let common : Array[(String, Setting)] = [
  ("kind", Text),
  ("filter", Text),
  ("level", Text),
  ("layout", Text),
  ("colour", Flag),
  ("retries", Count),
  ("probe", Span),
]

///|
/// What a setting of this kind wants, in the words of a refusal.
fn wanted(setting : Setting) -> String {
  match setting {
    Text => "a string"
    Flag => "true or false"
    Count => "a number"
    Size => "a size such as 10mb"
    Span => "a span such as 5s"
    Texts => "a list of strings"
    Pairs => "a table of strings"
  }
}

///|
/// Whether a value has the shape a setting asks for.
fn shaped(setting : Setting, value : Json, at : String) -> Unit raise Refused {
  match setting {
    Text =>
      if as_text(value) is None {
        raise refuse(at, shown(value), wanted(setting))
      }
    Flag =>
      if as_flag(value) is None {
        raise refuse(at, shown(value), wanted(setting))
      }
    Count =>
      if as_count(value) is None {
        raise refuse(at, shown(value), wanted(setting))
      }
    Size =>
      match as_text(value) {
        Some(text) => ignore(parse_size(at, text))
        None =>
          if as_count(value) is None {
            raise refuse(at, shown(value), wanted(setting))
          }
      }
    Span =>
      match as_text(value) {
        Some(text) => ignore(parse_span(at, text))
        None => raise refuse(at, shown(value), wanted(setting))
      }
    Texts =>
      match as_list(value) {
        Some(items) =>
          for item in items {
            if as_text(item) is None {
              raise refuse(at, shown(item), "a list of strings")
            }
          }
        None => raise refuse(at, shown(value), wanted(setting))
      }
    Pairs =>
      match as_table(value) {
        Some(pairs) =>
          for key, item in pairs {
            if as_text(item) is None {
              raise refuse(at + "." + key, shown(item), "a string")
            }
          }
        None => raise refuse(at, shown(value), wanted(setting))
      }
  }
}

///|
/// What a value is, for a refusal: a short description, not a whole document.
fn shown(value : Json) -> String {
  match value {
    String(text) => "`" + text + "`"
    True => "true"
    False => "false"
    Number(_, ..) => "a number"
    Null => "nothing"
    Array(_) => "a list"
    Object(_) => "a table"
  }
}
