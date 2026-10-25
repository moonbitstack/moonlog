// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a step may know about the moment it runs: the instant, in nanoseconds
/// since the epoch, handed in by whoever owns the clock.
pub(all) struct Env {
  now : Int64
}

///|
pub fn Env::at(now : Int64) -> Env {
  { now, }
}

///|
/// A step in a processor chain: it may change the record, or drop it.
///
/// A step that only decides returns the record it was given, untouched, so the
/// other slots still see what was written. The first step that changes
/// anything returns a copy.
pub(open) trait Processor {
  fn process(Self, Record, Env) -> Record?
}

///|
/// Masks fields by name at any depth or at a dotted path, and parts of the
/// message that match a pattern.
pub struct Redact {
  keys : Array[String]
  paths : Array[Array[String]]
  patterns : Array[@string.Regex]
  mut mask : String
}

///|
/// A step that masks nothing yet.
pub fn Redact::new() -> Redact {
  { keys: [], paths: [], patterns: [], mask: "***", }
}

///|
/// Masks these names wherever they appear.
pub fn Redact::key(self : Redact, key : String) -> Redact {
  self.keys.push(key)
  self
}

///|
/// Masks the field at a dotted path, such as `req.headers.authorization`.
pub fn Redact::path(self : Redact, path : String) -> Redact {
  self.paths.push(path.split(".").map(fn(part) { part.to_owned() }).collect())
  self
}

///|
/// Replaces whatever matches in the message.
pub fn Redact::pattern(
  self : Redact,
  pattern : StringView,
) -> Redact raise Refused {
  self.patterns.push(
    @string.Regex::Regex(pattern) catch {
      _ => raise refuse(0, pattern.to_owned(), "a regular expression")
    },
  )
  self
}

///|
/// What a masked value becomes; `***` unless set.
pub fn Redact::mask(self : Redact, mask : String) -> Redact {
  self.mask = mask
  self
}

///|
pub impl Processor for Redact with fn process(self, record, _env) {
  let mut masked = false
  for (name, value) in record.fields {
    if self.hits(name, value, [name]) {
      masked = true
      break
    }
  }
  let text = match self.patterns_at(record.msg) {
    Some(replaced) => {
      masked = true
      replaced
    }
    None => record.msg
  }
  if !masked {
    return Some(record)
  }
  let out = record.say(text)
  for i, (name, value) in out.fields {
    out.fields[i] = (name, self.scrub(value, [name]))
  }
  Some(out)
}

///|
pub extend Redact with Processor::{process}

///|
/// Whether `value` under `path` is to be masked, at this level or below.
fn Redact::hits(
  self : Redact,
  name : String,
  value : Value,
  path : Array[String],
) -> Bool {
  let _ = name
  if self.hit_name(path) {
    return true
  }
  match value {
    Map(pairs) =>
      for (k, v) in pairs {
        let next = path.copy()
        next.push(k)
        if self.hits(k, v, next) {
          return true
        }
      }
    _ => ()
  }
  false
}

///|
fn Redact::hit_name(self : Redact, path : Array[String]) -> Bool {
  let mut hit = false
  for key in self.keys {
    if path[path.length() - 1] == key {
      hit = true
    }
  }
  for wanted in self.paths {
    if same_path(wanted, path) {
      hit = true
    }
  }
  hit
}

///|
fn same_path(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i, item in a {
    if item != b[i] {
      return false
    }
  }
  true
}

///|
fn Redact::scrub(self : Redact, value : Value, path : Array[String]) -> Value {
  if self.hit_name(path) {
    return Value::of_str(self.mask)
  }
  match value {
    Map(pairs) => {
      let out : Array[(String, Value)] = []
      for (k, v) in pairs {
        let next = path.copy()
        next.push(k)
        out.push((k, self.scrub(v, next)))
      }
      Map(out)
    }
    _ => value
  }
}

///|
/// The message with every pattern's matches replaced, or `None` when nothing
/// matched.
fn Redact::patterns_at(self : Redact, msg : String) -> String? {
  let mut text = msg
  let mut changed = false
  for pattern in self.patterns {
    let next = replace_all(pattern, text, self.mask)
    if next != text {
      changed = true
      text = next
    }
  }
  if changed {
    Some(text)
  } else {
    None
  }
}

///|
/// Every match of `pattern` in `text` replaced by `replacement`.
fn replace_all(
  pattern : @string.Regex,
  text : String,
  replacement : String,
) -> String {
  let out = StringBuilder()
  let mut rest = text[:]
  while true {
    match pattern.execute(rest) {
      Some(found) => {
        out.write_string(found.before().to_owned())
        out.write_string(replacement)
        let after = found.after()
        if after.length() >= rest.length() {
          rest = ""
          break
        }
        rest = after
      }
      None => break
    }
  }
  out.write_string(rest.to_owned())
  out.to_string()
}

///|
/// Escapes line breaks, tabs and other control characters, so a message cannot
/// forge a second line.
pub struct Sanitise {}

///|
pub fn Sanitise::new() -> Sanitise {
  Sanitise::{ }
}

///|
pub impl Processor for Sanitise with fn process(_self, record, _env) {
  let mut dirty = has_control(record.msg)
  for (_, value) in record.fields {
    if value is Str(text) && has_control(text) {
      dirty = true
      break
    }
  }
  if !dirty {
    return Some(record)
  }
  let out = record.say(clean(record.msg))
  for i, (name, value) in out.fields {
    out.fields[i] = match value {
      Str(text) => (name, Value::of_str(clean(text)))
      other => (name, other)
    }
  }
  Some(out)
}

///|
pub extend Sanitise with Processor::{process}

///|
fn has_control(text : String) -> Bool {
  for c in text {
    if c.to_int() < 32 || c.to_int() == 127 {
      return true
    }
  }
  false
}

///|
/// `\\n`, `\\r`, `\\t`, and `\\u{nnnn}` for the rest.
fn clean(text : String) -> String {
  let out = StringBuilder()
  for c in text {
    match c {
      '\n' => out.write_string("\\n")
      '\r' => out.write_string("\\r")
      '\t' => out.write_string("\\t")
      _ =>
        if c.to_int() < 32 || c.to_int() == 127 {
          out.write_string("\\u{")
          write_digits(out, c.to_int(), 4)
          out.write_char('}')
        } else {
          out.write_char(c)
        }
    }
  }
  out.to_string()
}

///|
/// Adds the same fields to every record.
pub struct Fields {
  pairs : Array[(String, Value)]
}

///|
pub fn Fields::new() -> Fields {
  { pairs: [], }
}

///|
pub fn Fields::set(self : Fields, key : String, value : Value) -> Fields {
  self.pairs.push((key, value))
  self
}

///|
pub impl Processor for Fields with fn process(self, record, _env) {
  if self.pairs.length() == 0 {
    return Some(record)
  }
  Some(record.sets(self.pairs))
}

///|
pub extend Fields with Processor::{process}

///|
/// Conditions on tags, fields and level; every one given must hold.
pub struct Keep {
  tags : Array[String]
  equals : Array[(String, String)]
  mut level : Level?
}

///|
pub fn Keep::new() -> Keep {
  { tags: [], equals: [], level: None, }
}

///|
/// Requires a tag.
pub fn Keep::tag(self : Keep, tag : String) -> Keep {
  self.tags.push(tag)
  self
}

///|
/// Requires a field whose text is `value`.
pub fn Keep::field(self : Keep, key : String, value : String) -> Keep {
  self.equals.push((key, value))
  self
}

///|
/// Requires `min` and above.
pub fn Keep::level(self : Keep, min : Level) -> Keep {
  self.level = Some(min)
  self
}

///|
/// Whether every condition holds for `record`.
pub fn Keep::holds(self : Keep, record : Record) -> Bool {
  match self.level {
    Some(min) => if !record.level.at_least(min) { return false }
    None => ()
  }
  for tag in self.tags {
    if !record.tagged(tag) {
      return false
    }
  }
  for (key, want) in self.equals {
    match record.field(key) {
      Some(value) => if value.to_text() != want { return false }
      None => return false
    }
  }
  true
}

///|
/// Keeps a record only when every condition holds — the `match` step.
pub struct Match {
  keep : Keep
}

///|
pub fn Match::new() -> Match {
  { keep: Keep::new(), }
}

///|
pub fn Match::tag(self : Match, tag : String) -> Match {
  ignore(self.keep.tag(tag))
  self
}

///|
pub fn Match::field(self : Match, key : String, value : String) -> Match {
  ignore(self.keep.field(key, value))
  self
}

///|
pub fn Match::level(self : Match, min : Level) -> Match {
  ignore(self.keep.level(min))
  self
}

///|
pub impl Processor for Match with fn process(self, record, _env) {
  if self.keep.holds(record) {
    Some(record)
  } else {
    None
  }
}

///|
pub extend Match with Processor::{process}

///|
/// Drops a record when every condition holds.
pub struct Exclude {
  keep : Keep
}

///|
pub fn Exclude::new() -> Exclude {
  { keep: Keep::new(), }
}

///|
pub fn Exclude::tag(self : Exclude, tag : String) -> Exclude {
  ignore(self.keep.tag(tag))
  self
}

///|
pub fn Exclude::field(self : Exclude, key : String, value : String) -> Exclude {
  ignore(self.keep.field(key, value))
  self
}

///|
pub fn Exclude::level(self : Exclude, min : Level) -> Exclude {
  ignore(self.keep.level(min))
  self
}

///|
pub impl Processor for Exclude with fn process(self, record, _env) {
  if self.keep.holds(record) {
    None
  } else {
    Some(record)
  }
}

///|
pub extend Exclude with Processor::{process}

///|
/// Keeps the first records of each level and message every period, then one in
/// so many after that.
pub struct Sample {
  first : Int32
  every : Int32
  per : Int64
  seen : Map[String, (Int64, Int32)]
}

///|
/// Keeps the first `first` records per `per` nanoseconds, then one in `every`.
pub fn Sample::new(first~ : Int32, every~ : Int32 = 1, per~ : Int64) -> Sample {
  { first, every: if every < 1 { 1 } else { every }, per, seen: Map([]), }
}

///|
pub impl Processor for Sample with fn process(self, record, env) {
  let key = record.level.value.to_string() + "\u{0}" + record.msg
  let (start, count) = match self.seen.get(key) {
    Some(slot) => slot
    None => (env.now, 0)
  }
  let mut from = start
  let mut n = count
  if env.now - from >= self.per {
    from = env.now
    n = 0
  }
  n = n + 1
  self.seen[key] = (from, n)
  if n <= self.first || (n - self.first) % self.every == 0 {
    Some(record)
  } else {
    None
  }
}

///|
pub extend Sample with Processor::{process}

///|
/// A token bucket: `rate` records a second, with bursts of up to `burst`.
pub struct Limit {
  rate : Double
  burst : Double
  mut level : Double
  mut at : Int64
  mut started : Bool
}

///|
pub fn Limit::new(rate~ : Double, burst~ : Double) -> Limit {
  let burst = if burst < 1.0 { 1.0 } else { burst }
  { rate, burst, level: burst, at: 0L, started: false, }
}

///|
pub impl Processor for Limit with fn process(self, record, env) {
  if !self.started {
    self.started = true
    self.at = env.now
  }
  let seconds = (env.now - self.at).to_double() / 1_000_000_000.0
  self.level = self.level + seconds * self.rate
  if self.level > self.burst {
    self.level = self.burst
  }
  self.at = env.now
  if self.level >= 1.0 {
    self.level = self.level - 1.0
    Some(record)
  } else {
    None
  }
}

///|
pub extend Limit with Processor::{process}

///|
/// Drops a record that repeats one kept within the window; the next record kept
/// carries `repeated`, the number dropped in between.
pub struct Dedupe {
  within : Int64
  seen : Map[String, (Int64, Int32)]
}

///|
pub fn Dedupe::new(within~ : Int64) -> Dedupe {
  { within, seen: Map([]), }
}

///|
pub impl Processor for Dedupe with fn process(self, record, env) {
  let key = record.level.value.to_string() +
    "\u{0}" +
    record.target +
    "\u{0}" +
    record.msg
  match self.seen.get(key) {
    Some((at, dropped)) =>
      if env.now - at < self.within {
        self.seen[key] = (at, dropped + 1)
        return None
      } else {
        self.seen[key] = (env.now, 0)
        if dropped > 0 {
          return Some(record.set("repeated", Value::of_int(dropped)))
        }
      }
    None => self.seen[key] = (env.now, 0)
  }
  Some(record)
}

///|
pub extend Dedupe with Processor::{process}
