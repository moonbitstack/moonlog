// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A field's value, typed.
///
/// Fields are carried as values rather than as text so a layout decides how
/// they read: `7` and `"7"` are the same three characters on a line and
/// different things in a JSON document.
pub(all) enum Value {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  Str(String)
  List(Array[Value])
  Map(Array[(String, Value)])
  Error(String, Array[String])
  Other(String)
} derive(Debug)

///|
pub extend Value with Debug::{to_repr}

///|
pub fn Value::of_null() -> Value {
  Null
}

///|
pub fn Value::of_bool(b : Bool) -> Value {
  Bool(b)
}

///|
pub fn Value::of_int(n : Int32) -> Value {
  Int(n.to_int64())
}

///|
pub fn Value::of_long(n : Int64) -> Value {
  Int(n)
}

///|
pub fn Value::of_float(x : Double) -> Value {
  Float(x)
}

///|
pub fn Value::of_str(s : StringView) -> Value {
  Str(s.to_owned())
}

///|
pub fn Value::of_list(items : Array[Value]) -> Value {
  List(items)
}

///|
pub fn Value::of_map(pairs : Array[(String, Value)]) -> Value {
  Map(pairs)
}

///|
/// An error with its chain of causes, the way `error` travels as a field.
pub fn Value::of_error(
  message~ : String,
  causes~ : Array[String] = [],
) -> Value {
  Error(message, causes)
}

///|
/// Anything else, shown as text.
pub fn Value::of_other(text : String) -> Value {
  Other(text)
}

///|
/// The text form: bare strings, `[a, b]` for a list, `{k=v}` for a map, and an
/// error with its causes after colons.
pub fn Value::to_text(self : Value) -> String {
  match self {
    Null => "null"
    Bool(b) => b.to_string()
    Int(n) => n.to_string()
    Float(x) => x.to_string()
    Str(s) => s
    Other(s) => s
    Error(message, causes) => {
      let out = StringBuilder()
      out.write_string(message)
      for cause in causes {
        out.write_string(": ")
        out.write_string(cause)
      }
      out.to_string()
    }
    List(items) => {
      let out = StringBuilder()
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(item.to_text())
      }
      out.write_char(']')
      out.to_string()
    }
    Map(pairs) => {
      let out = StringBuilder()
      out.write_char('{')
      for i, (k, v) in pairs {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(k)
        out.write_char('=')
        out.write_string(v.to_text())
      }
      out.write_char('}')
      out.to_string()
    }
  }
}

///|
/// The value as JSON.
pub fn Value::encode(self : Value) -> String {
  let out = StringBuilder()
  self.write_json(out)
  out.to_string()
}

///|
/// Writes the value as JSON into `out`.
pub fn Value::write_json(self : Value, out : StringBuilder) -> Unit {
  match self {
    Null => out.write_string("null")
    Bool(b) =>
      if b {
        out.write_string("true")
      } else {
        out.write_string("false")
      }
    Int(n) => out.write_string(n.to_string())
    Float(x) => {
      // JSON has no infinity and no NaN; the text form is what a pipeline can
      // still read, and it stays a string rather than a number that lies.
      let text = x.to_string()
      if text.contains(("inf" : StringView)) ||
        text.contains(("nan" : StringView)) {
        write_json_string(out, text)
      } else {
        out.write_string(text)
      }
    }
    Str(s) => write_json_string(out, s)
    Other(s) => write_json_string(out, s)
    Error(message, causes) => {
      out.write_string("{\"message\":")
      write_json_string(out, message)
      if causes.length() > 0 {
        out.write_string(",\"causes\":[")
        for i, cause in causes {
          if i > 0 {
            out.write_char(',')
          }
          write_json_string(out, cause)
        }
        out.write_char(']')
      }
      out.write_char('}')
    }
    List(items) => {
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_char(',')
        }
        item.write_json(out)
      }
      out.write_char(']')
    }
    Map(pairs) => {
      out.write_char('{')
      for i, (k, v) in pairs {
        if i > 0 {
          out.write_char(',')
        }
        write_json_string(out, k)
        out.write_char(':')
        v.write_json(out)
      }
      out.write_char('}')
    }
  }
}

///|
/// Writes `s` as a JSON string, quotes and control characters escaped.
pub fn write_json_string(out : StringBuilder, s : StringView) -> Unit {
  out.write_char('"')
  for c in s {
    match c {
      '"' => out.write_string("\\\"")
      '\\' => out.write_string("\\\\")
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c.to_int() < 32 {
          let code = c.to_int()
          out.write_string("\\u00")
          out.write_char(hex_digit(code / 16))
          out.write_char(hex_digit(code % 16))
        } else {
          out.write_char(c)
        }
    }
  }
  out.write_char('"')
}

///|
fn hex_digit(n : Int32) -> Char {
  if n < 10 {
    (48 + n).unsafe_to_char()
  } else {
    (87 + n).unsafe_to_char()
  }
}

///|
/// `s` bare when it cannot be mistaken for two fields, quoted the logfmt way
/// otherwise: empty, or holding a space, a quote or an `=`.
pub fn write_logfmt(out : StringBuilder, s : StringView) -> Unit {
  let mut bare = s.length() > 0
  if bare {
    for c in s {
      if c == '"' || c == '=' || c.is_whitespace() {
        bare = false
        break
      }
    }
  }
  if bare {
    out.write_string(s.to_owned())
  } else {
    write_json_string(out, s)
  }
}
