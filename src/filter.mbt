// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One directive of a filter: a target and the level it lets through, or `None`
/// for `off`.
struct Rule {
  target : String
  glob : Bool
  level : Level?
}

///|
/// Which records pass, by target, level and optionally message.
///
/// The syntax is the one `RUST_LOG` made familiar: comma-separated directives,
/// `app=debug` for a target, `app` for everything a target writes, `off` for
/// nothing, `*` inside a target, and a `/regex` at the end that the message must
/// match. A target matches itself and everything under it, split at `::`, `.`,
/// `:` or `/`, and the most specific directive wins.
pub struct Filter {
  mut base : Level?
  rules : Array[Rule]
  mut pattern : @string.Regex?
  mut pattern_text : String
}

///|
/// A filter that lets `min` and above through for every target.
pub fn Filter::at(min : Level) -> Filter {
  { base: Some(min), rules: [], pattern: None, pattern_text: "", }
}

///|
/// A filter that lets nothing through.
pub fn Filter::off() -> Filter {
  { base: None, rules: [], pattern: None, pattern_text: "", }
}

///|
pub fn Filter::parse(spec : StringView) -> Filter raise Refused {
  let text = spec.to_owned()
  let (body, pattern_text) = match text.find(("/" : StringView)) {
    Some(i) => (text[0:i].to_owned(), text[i + 1:].to_owned())
    None => (text, "")
  }
  let filter = if body.trim().length() == 0 {
    Filter::at(error)
  } else {
    Filter::off()
  }
  for directive in split_directives(body) {
    let at = position_of(body, directive)
    match directive.find(("=" : StringView)) {
      Some(i) => {
        let target = directive[0:i].trim()
        let word = directive[i + 1:].trim()
        let level = if word == ("off" : StringView) {
          None
        } else {
          Some(
            Level::parse(word) catch {
              _ =>
                raise refuse(
                  at,
                  directive.to_owned(),
                  "`target=level`, with a level name, a number or `off`",
                )
            },
          )
        }
        filter.rules.push({
          target: target.to_owned(),
          glob: target.contains(("*" : StringView)),
          level,
        })
      }
      None =>
        if directive == ("off" : StringView) {
          filter.base = None
        } else {
          match level_or_none(directive) {
            Some(level) => filter.base = Some(level)
            None =>
              filter.rules.push({
                target: directive.to_owned(),
                glob: false,
                level: Some({ name: "all", value: 0, colour: Colour::Plain, }),
              })
          }
        }
    }
  }
  filter.rules.sort_by(fn(a, b) { rule_order(a, b) })
  if pattern_text.length() > 0 {
    filter.pattern = Some(pattern_of(pattern_text, text))
    filter.pattern_text = pattern_text
  }
  filter
}

///|
/// A level by name, or `None` when the word is a target instead.
fn level_or_none(word : StringView) -> Level? {
  Some(Level::parse(word)) catch {
    _ => None
  }
}

///|
fn pattern_of(pattern : String, text : String) -> @string.Regex raise Refused {
  @string.Regex::Regex(pattern) catch {
    _ =>
      raise refuse(
        text.length() - pattern.length() - 1,
        pattern,
        "a regular expression",
      )
  }
}

///|
/// The directive split at commas, trimmed, empties left out.
fn split_directives(body : String) -> Array[StringView] {
  let out : Array[StringView] = []
  for part in body.split(",") {
    let word = part.trim()
    if word.length() > 0 {
      out.push(word)
    }
  }
  out
}

///|
/// Where `part` starts inside `body`, so a refusal points at the directive that
/// could not be read.
fn position_of(body : String, part : StringView) -> Int32 {
  match body.find(part) {
    Some(i) => i
    None => 0
  }
}

///|
/// Literal targets before wildcards, longer before shorter: the most specific
/// directive is the first one that matches.
fn rule_order(a : Rule, b : Rule) -> Int32 {
  let by_kind = a.glob.compare(b.glob)
  if by_kind != 0 {
    return by_kind
  }
  literal_length(b) - literal_length(a)
}

///|
fn literal_length(rule : Rule) -> Int32 {
  let mut n = 0
  for c in rule.target {
    if c != '*' {
      n = n + 1
    }
  }
  n
}

///|
/// Whether a record at `level` from `target` passes, before its message is read.
pub fn Filter::allows(self : Filter, level : Level, target : String) -> Bool {
  let min = match first_match(self.rules, target) {
    Some(rule) => rule.level
    None => self.base
  }
  match min {
    Some(min) => level.at_least(min)
    None => false
  }
}

///|
/// Whether the message passes the `/regex` part, when there is one.
pub fn Filter::admits(
  self : Filter,
  level : Level,
  target : String,
  msg : String,
) -> Bool {
  if !self.allows(level, target) {
    return false
  }
  match self.pattern {
    Some(pattern) => pattern.execute(msg) is Some(_)
    None => true
  }
}

///|
/// The lowest level any target lets through, or `None` when everything is off.
pub fn Filter::lowest(self : Filter) -> Level? {
  let mut lowest = self.base
  for rule in self.rules {
    match rule.level {
      Some(level) =>
        lowest = match lowest {
          Some(current) => {
            let name = if level.value < current.value { level } else { current }
            Some(name)
          }
          None => Some(level)
        }
      None => ()
    }
  }
  lowest
}

///|
/// Whether there is a `/regex` part.
pub fn Filter::has_pattern(self : Filter) -> Bool {
  self.pattern is Some(_)
}

///|
/// The spec this filter reads back as.
pub fn Filter::to_text(self : Filter) -> String {
  let out = StringBuilder()
  match self.base {
    Some(level) => out.write_string(level.name())
    None => out.write_string("off")
  }
  for rule in self.rules {
    out.write_char(',')
    out.write_string(rule.target)
    match rule.level {
      Some(level) =>
        if level.value != 0 {
          out.write_char('=')
          out.write_string(level.name())
        }
      None => out.write_string("=off")
    }
  }
  if self.pattern_text.length() > 0 {
    out.write_char('/')
    out.write_string(self.pattern_text)
  }
  out.to_string()
}

///|
/// The first directive that covers `target`, which is the most specific one
/// because the list is sorted that way.
fn first_match(rules : Array[Rule], target : String) -> Rule? {
  for rule in rules {
    if rule_matches(rule, target) {
      return Some(rule)
    }
  }
  None
}

///|
fn rule_matches(rule : Rule, target : String) -> Bool {
  if rule.glob {
    return glob(rule.target, target)
  }
  if !target.has_prefix(rule.target) {
    return false
  }
  let rest = target[rule.target.length():]
  if rest.length() == 0 {
    return true
  }
  rest.has_prefix("::") ||
  rest.has_prefix(".") ||
  rest.has_prefix(":") ||
  rest.has_prefix("/")
}

///|
/// `*` matches any run of characters, including none.
fn glob(pattern : String, text : String) -> Bool {
  let p = pattern.to_array()
  let t = text.to_array()
  glob_at(p, 0, t, 0)
}

///|
fn glob_at(
  pattern : Array[Char],
  pi : Int32,
  text : Array[Char],
  ti : Int32,
) -> Bool {
  if pi == pattern.length() {
    return ti == text.length()
  }
  if pattern[pi] == '*' {
    let mut i = ti
    while i <= text.length() {
      if glob_at(pattern, pi + 1, text, i) {
        return true
      }
      i = i + 1
    }
    return false
  }
  if ti == text.length() || pattern[pi] != text[ti] {
    return false
  }
  glob_at(pattern, pi + 1, text, ti + 1)
}
