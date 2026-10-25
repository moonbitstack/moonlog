// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A line template: literal text with `{token}` or `{token:options}` holes, and
/// `{{` and `}}` for literal braces.
///
/// Every token but `time` may end with `<N`, `>N` or `^N` to pad to N columns,
/// then `.M` to keep at most M characters. `^` puts the extra space on the
/// right, which is what centred columns do in the loggers this reproduces.
pub struct Pattern {
  source : String
  pieces : Array[Piece]
  shows_error : Bool
  labels : Profile?
}

///|
/// One part of a pattern: a hole, or the text between two of them.
pub struct Piece {
  kind : Kind
  fit : Fit
}

///|
pub struct Fit {
  align : (Char, Int32)?
  max : Int32?
}

///|
/// What a hole asks for.
pub enum Kind {
  Text(String)
  Time(Clock)
  Level(Bool)
  Target(Int32)
  Module
  Func
  File(Bool)
  Line
  Thread
  Tid
  Task
  Pid
  Host
  App
  Env
  Instance
  Msg(Bool)
  Fields(Bool)
  Tags
  Error
  Elapsed
  Seq
  Spans
}

///|
/// A pattern, or the name of a preset standing for one.
pub fn Pattern::parse(text : StringView) -> Pattern raise Refused {
  let preset = preset_of(text)
  let source = match preset {
    Some(profile) => profile.pattern().to_owned()
    None => text.to_owned()
  }
  let pieces : Array[Piece] = []
  let literal = StringBuilder()
  let chars = source.to_array()
  let mut i = 0
  let mut shows_error = false
  while i < chars.length() {
    let c = chars[i]
    if c == '{' && i + 1 < chars.length() && chars[i + 1] == '{' {
      literal.write_char('{')
      i = i + 2
    } else if c == '}' && i + 1 < chars.length() && chars[i + 1] == '}' {
      literal.write_char('}')
      i = i + 2
    } else if c == '{' {
      let mut end = i + 1
      while end < chars.length() && chars[end] != '}' {
        end = end + 1
      }
      if end == chars.length() {
        raise refuse(i, "{", "a closing `}`")
      }
      flush_literal(literal, pieces)
      let hole = chars_to_string(chars[i + 1:end])
      let piece = read_piece(hole, i)
      if piece.kind is Error {
        shows_error = true
      }
      pieces.push(piece)
      i = end + 1
    } else if c == '}' {
      raise refuse(i, "}", "`}}` for a literal brace")
    } else {
      literal.write_char(c)
      i = i + 1
    }
  }
  flush_literal(literal, pieces)
  { source: text.to_owned(), pieces, shows_error, labels: preset, }
}

///|
fn flush_literal(literal : StringBuilder, pieces : Array[Piece]) -> Unit {
  let text = literal.to_string()
  if text.length() > 0 {
    pieces.push({ kind: Text(text), fit: { align: None, max: None, }, })
    ignore(literal.reset())
  }
}

///|
/// Reads `name` or `name:options` into a piece.
fn read_piece(hole : String, at : Int32) -> Piece raise Refused {
  let (name, spec) = match hole.find((":" : StringView)) {
    Some(i) => (hole[0:i], hole[i + 1:])
    None => (hole, "")
  }
  let name = name.trim()
  if name == ("time" : StringView) {
    return { kind: Time(Clock::parse(spec)), fit: { align: None, max: None, }, }
  }
  let mut rest = spec
  let kind = match name {
    "level" => {
      let (on, tail) = option(rest, "lower")
      rest = tail
      Level(on)
    }
    "target" => {
      let (n, tail) = short_target(rest)
      rest = tail
      Target(n)
    }
    "file" => {
      let (on, tail) = option(rest, "base")
      rest = tail
      File(on)
    }
    "msg" => {
      let (on, tail) = option(rest, "q")
      rest = tail
      Msg(on)
    }
    "fields" => {
      let (on, tail) = option(rest, "q")
      rest = tail
      Fields(on)
    }
    "error" => {
      let (_on, tail) = option(rest, "stack")
      rest = tail
      Error
    }
    "module" => Module
    "func" => Func
    "line" => Line
    "thread" => Thread
    "tid" => Tid
    "task" => Task
    "pid" => Pid
    "host" => Host
    "app" => App
    "env" => Env
    "instance" => Instance
    "tags" => Tags
    "elapsed" => Elapsed
    "seq" => Seq
    "spans" => Spans
    _ => raise refuse(at, name.to_owned(), "a token this library knows")
  }
  { kind, fit: read_fit(rest, at), }
}

///|
/// `~N` after `target`: shorten leading segments to fit N columns.
fn short_target(spec : StringView) -> (Int32, StringView) {
  if !spec.has_prefix("~") {
    return (-1, spec)
  }
  let digits = digits_prefix(spec[1:])
  if digits == 0 {
    return (-1, spec)
  }
  (parse_number(spec[1:1 + digits]), spec[1 + digits:])
}

///|
fn option(spec : StringView, word : String) -> (Bool, StringView) {
  if spec.has_prefix(word) {
    (true, spec[word.length():])
  } else {
    (false, spec)
  }
}

///|
/// The width and truncation a spec ends with.
fn read_fit(spec : StringView, at : Int32) -> Fit raise Refused {
  if spec.length() == 0 {
    return { align: None, max: None, }
  }
  let chars = spec.to_array()
  let mut i = 0
  let mut align = None
  if chars[0] == '<' || chars[0] == '>' || chars[0] == '^' {
    let n = digits_prefix(spec[1:])
    if n == 0 {
      raise refuse(at, spec.to_owned(), "a width after the alignment mark")
    }
    align = Some((chars[0], parse_number(spec[1:1 + n])))
    i = 1 + n
  }
  let rest = spec[i:]
  let mut max = None
  if rest.length() > 0 {
    if !rest.has_prefix(".") {
      raise refuse(at, rest.to_owned(), "a width such as `<7` or `.4`")
    }
    let n = digits_prefix(rest[1:])
    if n == 0 || n != rest.length() - 1 {
      raise refuse(at, rest.to_owned(), "a number after `.`")
    }
    max = Some(parse_number(rest[1:]))
  }
  { align, max, }
}

///|
fn digits_prefix(text : StringView) -> Int32 {
  let chars = text.to_array()
  let mut n = 0
  while n < chars.length() && chars[n] >= '0' && chars[n] <= '9' {
    n = n + 1
  }
  n
}

///|
fn parse_number(text : StringView) -> Int32 {
  let mut n = 0
  for c in text {
    n = n * 10 + (c.to_int() - 48)
  }
  n
}

///|
/// The text it was parsed from.
pub fn Pattern::source(self : Pattern) -> String {
  self.source
}

///|
/// Writes one record through the pattern.
pub fn Pattern::render_line(
  self : Pattern,
  record : Record,
  scene : Scene,
) -> String {
  let out = StringBuilder()
  for piece in self.pieces {
    match piece.kind {
      Text(text) => out.write_string(text)
      kind => {
        let token = StringBuilder()
        write_token(token, kind, record, scene, self.labels, self.shows_error)
        let word = fit(token.to_string(), piece.fit)
        if scene.colour && kind is Level(_) {
          out.write_string(record.level.colour.ansi())
          out.write_string(word)
          out.write_string(reset)
        } else {
          out.write_string(word)
        }
      }
    }
  }
  out.to_string()
}

///|
/// Truncates to the maximum, then pads to the width.
fn fit(text : String, fit : Fit) -> String {
  let mut word = text
  match fit.max {
    Some(max) => {
      let chars = word.to_array()
      if chars.length() > max {
        word = chars_to_string(chars[0:max])
      }
    }
    None => ()
  }
  match fit.align {
    Some((mark, width)) => pad(word, width, mark)
    None => word
  }
}

///|
/// Pads `text` to `width` characters; `^` leaves the extra space on the right.
fn pad(text : StringView, width : Int32, mark : Char) -> String {
  let length = text.char_length()
  if length >= width {
    return text.to_owned()
  }
  let gap = width - length
  if mark == '>' {
    spaces(gap) + text.to_owned()
  } else if mark == '^' {
    let left = gap / 2
    spaces(left) + text.to_owned() + spaces(gap - left)
  } else {
    text.to_owned() + spaces(gap)
  }
}

///|
fn spaces(n : Int32) -> String {
  let out = StringBuilder()
  for _ in 0..<n {
    out.write_char(' ')
  }
  out.to_string()
}

///|
/// One token, before padding.
fn write_token(
  out : StringBuilder,
  kind : Kind,
  record : Record,
  scene : Scene,
  labels : Profile?,
  shows_error : Bool,
) -> Unit {
  match kind {
    Text(text) => out.write_string(text)
    Time(clock) =>
      clock.write(out, record.time, (scene.identity.offset)(record.time))
    Level(lower) =>
      if lower {
        out.write_string(record.level.name())
      } else {
        let profile = match labels {
          Some(profile) => profile
          None => scene.profile
        }
        out.write_string(record.level.label(profile))
      }
    Target(shorten_for) =>
      if shorten_for < 0 {
        out.write_string(record.target)
      } else {
        out.write_string(shorten(record.target, shorten_for))
      }
    Module =>
      match record.caller.module_path {
        Some(path) => out.write_string(path)
        None => out.write_string(record.target)
      }
    Func =>
      match record.caller.func {
        Some(func) => out.write_string(func)
        None => out.write_char('?')
      }
    File(base) =>
      match record.caller.file {
        Some(file) =>
          if base {
            out.write_string(base_name(file))
          } else {
            out.write_string(file)
          }
        None => out.write_char('?')
      }
    Line =>
      match record.caller.line {
        Some(line) => out.write_string(line.to_string())
        None => out.write_char('?')
      }
    Thread =>
      match record.thread {
        Some(thread) => out.write_string(thread)
        None => out.write_char('?')
      }
    Tid | Task => out.write_char('?')
    Pid => out.write_string(scene.identity.pid.to_string())
    Host => out.write_string(scene.identity.host)
    App => out.write_string(scene.identity.app)
    Env => out.write_string(scene.identity.env)
    Instance => out.write_string(scene.identity.instance)
    Msg(quoted) =>
      if quoted {
        write_logfmt(out, record.msg)
      } else {
        out.write_string(record.msg)
      }
    Fields(quoted) => write_fields(out, record, quoted, shows_error)
    Tags =>
      for i, tag in record.tags {
        if i > 0 {
          out.write_char(',')
        }
        out.write_string(tag)
      }
    Error =>
      match record.field("error") {
        Some(value) => out.write_string(value.to_text())
        None => ()
      }
    Elapsed => out.write_string(elapsed_ms(record, scene.identity).to_string())
    Seq => out.write_string(record.seq.to_string())
    Spans =>
      match record.spans {
        Some(chain) =>
          if chain.length() > 0 {
            out.write_string(chain)
            out.write_string(": ")
          }
        None => ()
      }
  }
}
