// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A logging configuration, read from a document and checked against the
/// settings the shipped sinks read.
///
/// Reading a document does not build anything: it says what the deployment
/// asked for, and the application — or `moonlog/global` — turns that into
/// sinks. That split is what lets the same document be checked, dumped and
/// reloaded without a file system in the way.
pub(all) struct Config {
  mut profile : @moonlog.Profile
  mut filter : String
  mut slots : Array[Slot]
  mut alarm : Alarm?
  /// The deployment's own name, and what it calls its environment and node:
  /// the identity a record carries. Empty when the document says nothing.
  mut app : String
  mut env : String
  mut instance : String
  /// Levels the document defines by name, for a filter or a slot to use.
  mut levels : Array[@moonlog.Level]
  /// The chain every record walks before a slot sees it: `process` and the
  /// `redact` shorthand, in the order they apply.
  mut chain : Array[&@moonlog.Processor]
  /// Those same steps as the document wrote them, which is what `dump` writes
  /// back: a built processor cannot be asked for its options.
  mut process : Array[Json]
  /// Alarms the document names, which a sink's `on_fail` may point at.
  mut alarms : Array[(String, Alarm)]
  /// How often the document asks for its file to be checked, when it says.
  mut watch : Int64?
  /// A variable whose value overrides `filter`.
  mut filter_env : String?
}

///|
/// One sink as the document describes it.
///
/// `settings` holds the keys that belong to the kind; `text`, `flag`, `size`
/// and the rest read them back with the shape the parser already checked.
pub(all) struct Slot {
  name : String
  kind : String
  mut filter : String?
  layout : String?
  colour : Bool?
  retries : Int32?
  probe : Int64?
  queue : Queue?
  /// The steps this slot runs before its layout, in the order it runs them.
  mut chain : Array[&@moonlog.Processor]
  /// Those steps as the document wrote them, which is what `dump` writes back.
  mut process : Array[Json]
  /// The alarm an incident on this sink goes to, by name; nothing means the
  /// document's default alarm.
  mut on_fail : String?
  /// Whether the sink is kept off the log route and takes incidents only.
  mut alarm_only : Bool
  settings : Map[String, Json]
}

///|
/// A queue as a document writes it.
pub(all) struct Queue {
  size : Int32
  batch : Int32
  wait : Int64
  full : @moonlog.Full
}

///|
/// An alarm as a document writes it: which sinks to try, in which tiers, how
/// often to remind, and what to do when every tier is spent.
pub(all) struct Alarm {
  tiers : Array[Array[String]]
  remind : Int64
  fallback : @moonlog.Fallback
}

///|
/// One second, the reminder an alarm gets when the document does not say.
pub let remind_default : Int64 = 900_000_000_000L

///|
/// What a configuration with no document says: the default profile, the
/// default filter, and nothing to write to.
pub fn Config::new() -> Config {
  {
    profile: @moonlog.Profile::Serlog,
    filter: "",
    slots: [],
    alarm: None,
    app: "",
    env: "",
    instance: "",
    levels: [],
    chain: [],
    process: [],
    alarms: [],
    watch: None,
    filter_env: None,
  }
}

///|
/// The profile the document asks for.
pub fn Config::profile(self : Config) -> @moonlog.Profile {
  self.profile
}

///|
/// The filter the document asks for, as written.
pub fn Config::filter(self : Config) -> String {
  self.filter
}

///|
/// The slots the document describes, in document order.
pub fn Config::slots(self : Config) -> Array[Slot] {
  self.slots
}

///|
/// The slot called `name`, if there is one.
pub fn Config::slot(self : Config, name : String) -> Slot? {
  for slot in self.slots {
    if slot.name == name {
      return Some(slot)
    }
  }
  None
}

///|
/// The alarm the document describes, if any.
pub fn Config::alarm(self : Config) -> Alarm? {
  self.alarm
}

///|
/// The alarm as the hub wants it.
pub fn Alarm::tiers(self : Alarm) -> @moonlog.Tiers {
  @moonlog.Tiers::from(self.tiers)
  .with_remind(self.remind)
  .with_fallback(self.fallback)
}

///|
/// Reads a document.
///
/// `${NAME}` in any string is replaced by the environment variable of that
/// name; a name the environment does not have is refused, because a
/// configuration that silently logs to an empty URL is worse than one that
/// will not start.
pub fn Config::parse(
  text : StringView,
  format~ : Format = Format::Yaml,
  lookup~ : (String) -> String? = fn(name) { @env.get_env_var(name) },
) -> Config raise Refused {
  let tree = format.read(text, "")
  let root = match as_table(tree) {
    Some(root) => root
    None => raise refuse("", shown(tree), "a table")
  }
  // Two spellings of one model: a document that lists `sinks`, names its
  // profile `compat` or its alarms in a table is the shared specification's,
  // and is read by `spec_of`.
  if root.get("sinks") is Some(_) || root.get("compat") is Some(_) {
    return spec_of(root, lookup)
  }
  let config = Config::new()
  match root.get("levels") {
    Some(value) => config.levels = levels_of(value)
    None => ()
  }
  let mut steps = None
  let mut redacted = None
  for key, value in root {
    match key {
      "profile" => config.profile = profile_of(key, value)
      "filter" =>
        config.filter = levels_named(
          substitute(key, value, lookup),
          config.levels,
        )
      "slots" => config.slots = slots_of(value, lookup)
      "alarm" => config.alarm = Some(alarm_of(value, lookup))
      "app" => config.app = word(key, value)
      "env" => config.env = word(key, value)
      "instance" => config.instance = word(key, value)
      "levels" => ()
      "process" => steps = Some(value)
      "redact" => redacted = Some(value)
      "alarms" => config.alarms = alarms_of(value, lookup)
      "watch" => config.watch = Some(parse_span(key, word(key, value)))
      "filter_env" => config.filter_env = Some(word(key, value))
      _ =>
        raise refuse(
          key,
          "a key",
          "profile, filter, slots, alarm, app, env, instance, levels, " +
          "process, redact, alarms, watch or filter_env",
        )
    }
  }
  build_chain(config, steps, redacted)
  for pair in config.alarms {
    if pair.0 == "default" {
      config.alarm = Some(pair.1)
    }
  }
  config
}

///|
/// The profile a document names.
fn profile_of(at : String, value : Json) -> @moonlog.Profile raise Refused {
  let name = match as_text(value) {
    Some(name) => name
    None => raise refuse(at, shown(value), "a profile name")
  }
  @moonlog.Profile::parse(name) catch {
    _ => raise refuse(at, "`" + name + "`", "one of the seven profiles")
  }
}

///|
/// The slots a document describes.
fn slots_of(
  value : Json,
  lookup : (String) -> String?,
) -> Array[Slot] raise Refused {
  let table = match as_table(value) {
    Some(table) => table
    None => raise refuse("slots", shown(value), "a table of slots")
  }
  let slots : Array[Slot] = []
  for name, body in table {
    slots.push(slot_of(name, body, lookup))
  }
  slots
}

///|
/// One slot, checked key by key against the settings its kind reads.
fn slot_of(
  name : String,
  body : Json,
  lookup : (String) -> String?,
  at? : String,
  levels? : Array[@moonlog.Level],
) -> Slot raise Refused {
  let at = at.unwrap_or("slots." + name)
  let levels = levels.unwrap_or([])
  let table = match as_table(body) {
    Some(table) => table
    None => raise refuse(at, shown(body), "a table")
  }
  let kind = match table.get("kind") {
    Some(value) =>
      match as_text(value) {
        Some(kind) => kind
        None => raise refuse(at + ".kind", shown(value), "a string")
      }
    None => raise missing(at + ".kind", "the kind of sink this is")
  }
  let known = match settings_of(kind) {
    Some(known) => known
    None =>
      raise refuse(
        at + ".kind",
        "`" + kind + "`",
        "console, file, loki, mail, memory or discard",
      )
  }
  let settings = Map([])
  for key, value in table {
    let setting = match setting_of(known, key) {
      Some(setting) => Some(setting)
      None => setting_of(common, key)
    }
    if key == "queue" || key == "process" {
      // A queue and a chain are read below: one may be a table or a number,
      // the other is a list of steps.
      continue
    }
    match setting {
      Some(setting) => shaped(setting, value, at + "." + key)
      None =>
        raise refuse(
          at + "." + key,
          "a key",
          "one of " + names_of(known) + ", or one every slot has",
        )
    }
    if key != "kind" &&
      key != "filter" &&
      key != "level" &&
      key != "layout" &&
      key != "colour" &&
      key != "retries" &&
      key != "probe" &&
      key != "queue" &&
      key != "batch" &&
      key != "wait" &&
      key != "full" &&
      key != "process" &&
      key != "on_fail" &&
      key != "alarm_only" {
      settings[key] = substituted(at + "." + key, value, lookup)
    }
  }
  // `level` and `filter` say the same thing in different words, so a document
  // may have one or the other and not both.
  if table.get("filter") is Some(_) && table.get("level") is Some(_) {
    raise refuse(
      at + ".filter",
      "a key beside `level`",
      "`level` or `filter`, not both",
    )
  }
  let filter = match table.get("filter") {
    Some(value) =>
      Some(levels_named(substitute(at + ".filter", value, lookup), levels))
    None =>
      match table.get("level") {
        Some(value) =>
          Some(levels_named(substitute(at + ".level", value, lookup), levels))
        None => None
      }
  }
  let layout = match table.get("layout") {
    Some(value) => Some(substitute(at + ".layout", value, lookup))
    None => None
  }
  let (chain, process) = match table.get("process") {
    Some(value) => {
      let items = match as_list(value) {
        Some(items) => items
        None => raise refuse(at + ".process", shown(value), "a list of steps")
      }
      let chain = chain_of(at + ".process", value, levels)
      let written : Array[Json] = []
      for item in items {
        written.push(item)
      }
      (chain, written)
    }
    None => {
      let none : Array[&@moonlog.Processor] = []
      let empty : Array[Json] = []
      (none, empty)
    }
  }
  {
    name,
    kind,
    filter,
    layout,
    colour: match table.get("colour") {
      Some(value) =>
        match as_flag(value) {
          Some(flag) => Some(flag)
          None =>
            match as_text(value) {
              Some("always") => Some(true)
              Some("never") => Some(false)
              Some("auto") => None
              _ =>
                raise refuse(
                  at + ".colour",
                  shown(value),
                  "auto, always or never",
                )
            }
        }
      None => None
    },
    retries: match table.get("retries") {
      Some(value) =>
        match as_count(value) {
          Some(n) => Some(n.to_int())
          None => None
        }
      None => None
    },
    probe: match table.get("probe") {
      Some(value) =>
        match as_text(value) {
          Some(text) =>
            Some(parse_span(at + ".probe", text)) catch {
              _ => None
            }
          None => None
        }
      None => None
    },
    queue: queue_at(at, table),
    chain,
    process,
    on_fail: match table.get("on_fail") {
      Some(value) => Some(substitute(at + ".on_fail", value, lookup))
      None => None
    },
    alarm_only: match table.get("alarm_only") {
      Some(value) =>
        match as_flag(value) {
          Some(flag) => flag
          None => false
        }
      None => false
    },
    settings,
  }
}

///|
/// The queue a sink entry asks for.
///
/// Two spellings: a table of `size`, `batch`, `wait` and `full`, and the flat
/// one a deployment file usually arrives in — `queue: 8192` with `batch`,
/// `wait` and `full` beside it, where `0` means the sink writes directly.
fn queue_at(at : String, table : Map[String, Json]) -> Queue? raise Refused {
  let flat = table.get("batch") is Some(_) ||
    table.get("wait") is Some(_) ||
    table.get("full") is Some(_)
  match table.get("queue") {
    Some(value) =>
      match as_count(value) {
        Some(number) => {
          if number < 0.0 {
            raise refuse(
              at + ".queue",
              shown(value),
              "a number of records, or 0",
            )
          }
          let size = number.to_int()
          if size == 0 {
            if flat {
              raise refuse(
                at + ".batch",
                "a key beside `queue: 0`",
                "a queue, or none: `queue: 0` writes directly",
              )
            }
            None
          } else {
            Some(queue_with(at, table, size))
          }
        }
        None => queue_of(at + ".queue", value)
      }
    None =>
      if flat {
        // The sink's own queue, with the parts the document named in it.
        Some(queue_with(at, table, @moonlog.batch_default * 16))
      } else {
        None
      }
  }
}

///|
/// A queue of `size`, with the parts the document named beside it.
fn queue_with(
  at : String,
  table : Map[String, Json],
  size : Int32,
) -> Queue raise Refused {
  {
    size,
    batch: count_at("batch", at, table, @moonlog.batch_default),
    wait: span_at("wait", at, table, @moonlog.wait_default),
    full: full_at("full", at, table),
  }
}

///|
/// A whole number beside the queue, or the default.
fn count_at(
  key : String,
  at : String,
  table : Map[String, Json],
  fallback : Int32,
) -> Int32 raise Refused {
  match table.get(key) {
    Some(value) =>
      match as_count(value) {
        Some(number) => number.to_int()
        None => raise refuse(at + "." + key, shown(value), "a number")
      }
    None => fallback
  }
}

///|
/// A span beside the queue, or the default.
fn span_at(
  key : String,
  at : String,
  table : Map[String, Json],
  fallback : Int64,
) -> Int64 raise Refused {
  match table.get(key) {
    Some(value) =>
      match as_text(value) {
        Some(text) => parse_span(at + "." + key, text)
        None => raise refuse(at + "." + key, shown(value), "a span such as 1s")
      }
    None => fallback
  }
}

///|
/// What a full queue does, beside the queue, or the default.
fn full_at(
  key : String,
  at : String,
  table : Map[String, Json],
) -> @moonlog.Full raise Refused {
  match table.get(key) {
    Some(value) =>
      match as_text(value) {
        Some("drop") => @moonlog.Full::Drop
        Some("block") => @moonlog.Full::Block
        _ => raise refuse(at + "." + key, shown(value), "drop or block")
      }
    None => @moonlog.Full::Drop
  }
}

///|
/// A filter with the levels the document defined put in as their values: a
/// filter names a level by number, and a level defined in the document has one.
fn levels_named(spec : String, levels : Array[@moonlog.Level]) -> String {
  if levels.length() == 0 || spec == "" {
    return spec
  }
  let out = StringBuilder()
  let mut first = true
  for directive in spec.split(",") {
    if !first {
      out.write_char(',')
    }
    first = false
    let (body, pattern) = match directive.find("/") {
      Some(at) => (directive[:at].to_owned(), directive[at:].to_owned())
      None => (directive.to_owned(), "")
    }
    let trimmed = body.trim()
    let (target, level) = match trimmed.find("=") {
      Some(at) => (trimmed[:at].to_owned() + "=", trimmed[at + 1:].to_owned())
      None => ("", trimmed.to_owned())
    }
    let mut value = level
    for defined in levels {
      if defined.name == level {
        value = defined.value.to_string()
      }
    }
    out.write_string(target)
    out.write_string(value)
    out.write_string(pattern)
  }
  out.to_string()
}

///|
/// The settings a kind reads.
fn settings_of(kind : String) -> Array[(String, Setting)]? {
  // The console answers to both names it goes by: the one a document written
  // for the specification uses, and this package's own.
  let wanted = if kind == "console" { "stdio" } else { kind }
  for pair in kinds {
    if pair.0 == wanted {
      return Some(pair.1)
    }
  }
  None
}

///|
/// What a key holds in one table of settings.
fn setting_of(table : Array[(String, Setting)], key : String) -> Setting? {
  for pair in table {
    if pair.0 == key {
      return Some(pair.1)
    }
  }
  None
}

///|
/// The names of the settings a kind reads, for a refusal message.
fn names_of(settings : Array[(String, Setting)]) -> String {
  let names : Array[String] = []
  for pair in settings {
    names.push(pair.0)
  }
  names.join(", ")
}

///|
/// A queue, checked.
fn queue_of(at : String, value : Json) -> Queue? raise Refused {
  let table = match as_table(value) {
    Some(table) => table
    None =>
      raise refuse(at, shown(value), "a table with size, batch, wait and full")
  }
  let size = match table.get("size") {
    Some(value) =>
      match as_count(value) {
        Some(n) => n.to_int()
        None => raise refuse(at + ".size", shown(value), "a number")
      }
    None => raise missing(at + ".size", "how many records the queue holds")
  }
  let batch = match table.get("batch") {
    Some(value) =>
      match as_count(value) {
        Some(n) => n.to_int()
        None => raise refuse(at + ".batch", shown(value), "a number")
      }
    None => @moonlog.batch_default
  }
  let wait = match table.get("wait") {
    Some(value) =>
      match as_text(value) {
        Some(text) => parse_span(at + ".wait", text)
        None => raise refuse(at + ".wait", shown(value), "a span such as 1s")
      }
    None => @moonlog.wait_default
  }
  let full = match table.get("full") {
    Some(value) => {
      let name = match as_text(value) {
        Some(name) => name
        None => raise refuse(at + ".full", shown(value), "drop or block")
      }
      match name {
        "drop" => @moonlog.Full::Drop
        "block" => @moonlog.Full::Block
        _ => raise refuse(at + ".full", "`" + name + "`", "drop or block")
      }
    }
    None => @moonlog.Full::Drop
  }
  Some({ size, batch, wait, full, })
}

///|
/// The alarm a document describes.
fn alarm_of(value : Json, lookup : (String) -> String?) -> Alarm raise Refused {
  let at = "alarm"
  let table = match as_table(value) {
    Some(table) => table
    None =>
      raise refuse(at, shown(value), "a table with tiers, remind and fallback")
  }
  let tiers : Array[Array[String]] = []
  match table.get("tiers") {
    Some(value) =>
      match as_list(value) {
        Some(rows) =>
          for row in rows {
            let names : Array[String] = []
            match as_list(row) {
              Some(items) =>
                for item in items {
                  match as_text(item) {
                    Some(name) => names.push(name)
                    None =>
                      raise refuse(
                        at + ".tiers",
                        shown(item),
                        "a tier of slot names",
                      )
                  }
                }
              None =>
                raise refuse(at + ".tiers", shown(row), "a tier of slot names")
            }
            tiers.push(names)
          }
        None => raise refuse(at + ".tiers", shown(value), "a list of tiers")
      }
    None => raise missing(at + ".tiers", "the sinks an alarm walks")
  }
  let remind = match table.get("remind") {
    Some(value) =>
      match as_text(value) {
        Some(text) => parse_span(at + ".remind", text)
        None => raise refuse(at + ".remind", shown(value), "a span such as 30m")
      }
    None => remind_default
  }
  // A document may call an alarm's fallback `on_fail`, the way the shared
  // specification does, or `fallback`, the way this package always has.
  let wanted = match table.get("fallback") {
    Some(value) => Some(value)
    None => table.get("on_fail")
  }
  let fallback = match wanted {
    Some(value) => {
      let name = substitute(at + ".fallback", value, lookup)
      match name {
        "ignore" => @moonlog.Fallback::Ignore
        "panic" => @moonlog.Fallback::Panic
        _ => raise refuse(at + ".fallback", "`" + name + "`", "ignore or panic")
      }
    }
    None => @moonlog.Fallback::Ignore
  }
  { tiers, remind, fallback, }
}

///|
/// A value with every `${NAME}` in it replaced, including inside lists and
/// tables.
fn substituted(
  at : String,
  value : Json,
  lookup : (String) -> String?,
) -> Json raise Refused {
  match value {
    String(_) => Json::string(substitute(at, value, lookup))
    Array(items) => {
      let out : Array[Json] = []
      for item in items {
        out.push(substituted(at, item, lookup))
      }
      Json::array(out)
    }
    Object(entries) => {
      let out : Map[String, Json] = Map([])
      for key, item in entries {
        out[key] = substituted(at + "." + key, item, lookup)
      }
      Json::object(out)
    }
    _ => value
  }
}

///|
/// A name as a document writes it, put together without concatenation.
fn named(name : String) -> String {
  let out = StringBuilder()
  out.write_char('$')
  out.write_char('{')
  out.write_string(name)
  out.write_char('}')
  out.to_string()
}

///|
/// A string with `${NAME}` replaced, or any other value unchanged.
fn substitute(
  at : String,
  value : Json,
  lookup : (String) -> String?,
) -> String raise Refused {
  // A name is built character by character rather than concatenated: the
  // JavaScript backend folds `"$" + "{"` into a template literal, and the code
  // it emits for that does not parse.

  let text = match as_text(value) {
    Some(text) => text
    None => raise refuse(at, shown(value), "a string")
  }
  let out = StringBuilder()
  let chars = text.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '{' {
      let mut end = i + 2
      while end < chars.length() && chars[end] != '}' {
        end = end + 1
      }
      if end >= chars.length() {
        raise refuse(at, text, "a name opened with a brace and never closed")
      }
      let name = text[i + 2:end].to_owned()
      match lookup(name) {
        Some(replacement) => out.write_string(replacement)
        None => raise refuse(at, named(name), "a name the environment has")
      }
      i = end + 1
    } else {
      out.write_char(chars[i])
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// The document this configuration is written as.
pub fn Config::to_json(self : Config) -> Json {
  let root : Map[String, Json] = Map([])
  root["profile"] = Json::string(self.profile.name().to_owned())
  if self.filter != "" {
    root["filter"] = Json::string(self.filter)
  }
  if self.app != "" {
    root["app"] = Json::string(self.app)
  }
  if self.env != "" {
    root["env"] = Json::string(self.env)
  }
  if self.instance != "" {
    root["instance"] = Json::string(self.instance)
  }
  if self.levels.length() > 0 {
    let levels : Map[String, Json] = Map([])
    for level in self.levels {
      let body : Map[String, Json] = Map([])
      body["value"] = Json::number(level.value.to_double())
      body["colour"] = Json::string(level.colour.name().to_owned())
      levels[level.name] = Json::object(body)
    }
    root["levels"] = Json::object(levels)
  }
  if self.process.length() > 0 {
    root["process"] = Json::array(self.process)
  }
  match self.watch {
    Some(span) => root["watch"] = Json::string(nanos_as_span(span))
    None => ()
  }
  match self.filter_env {
    Some(name) => root["filter_env"] = Json::string(name)
    None => ()
  }
  if self.alarms.length() > 0 {
    let alarms : Map[String, Json] = Map([])
    for pair in self.alarms {
      alarms[pair.0] = alarm_json(pair.1)
    }
    root["alarms"] = Json::object(alarms)
  }
  let slots : Map[String, Json] = Map([])
  for slot in self.slots {
    let body : Map[String, Json] = Map([])
    body["kind"] = Json::string(slot.kind)
    match slot.filter {
      Some(filter) => body["filter"] = Json::string(filter)
      None => ()
    }
    match slot.layout {
      Some(layout) => body["layout"] = Json::string(layout)
      None => ()
    }
    match slot.colour {
      Some(colour) => body["colour"] = Json::boolean(colour)
      None => ()
    }
    match slot.retries {
      Some(retries) => body["retries"] = Json::number(retries.to_double())
      None => ()
    }
    match slot.probe {
      Some(probe) => body["probe"] = Json::string(nanos_as_span(probe))
      None => ()
    }
    if slot.process.length() > 0 {
      body["process"] = Json::array(slot.process)
    }
    match slot.on_fail {
      Some(name) => body["on_fail"] = Json::string(name)
      None => ()
    }
    if slot.alarm_only {
      body["alarm_only"] = Json::boolean(true)
    }
    match slot.queue {
      Some(queue) => {
        let held : Map[String, Json] = Map([])
        held["size"] = Json::number(queue.size.to_double())
        held["batch"] = Json::number(queue.batch.to_double())
        held["wait"] = Json::string(nanos_as_span(queue.wait))
        held["full"] = Json::string(
          match queue.full {
            @moonlog.Full::Drop => "drop"
            @moonlog.Full::Block => "block"
          },
        )
        body["queue"] = Json::object(held)
      }
      None => ()
    }
    for key, value in slot.settings {
      body[key] = value
    }
    slots[slot.name] = Json::object(body)
  }
  root["slots"] = Json::object(slots)
  match self.alarm {
    Some(alarm) => root["alarm"] = alarm_json(alarm)
    None => ()
  }
  Json::object(root)
}

///|
/// An alarm as a document writes it, under either name it may sit at.
fn alarm_json(alarm : Alarm) -> Json {
  let body : Map[String, Json] = Map([])
  let tiers : Array[Json] = []
  for tier in alarm.tiers {
    let names : Array[Json] = []
    for name in tier {
      names.push(Json::string(name))
    }
    tiers.push(Json::array(names))
  }
  body["tiers"] = Json::array(tiers)
  body["remind"] = Json::string(nanos_as_span(alarm.remind))
  body["on_fail"] = Json::string(
    match alarm.fallback {
      @moonlog.Fallback::Ignore => "ignore"
      @moonlog.Fallback::Panic => "panic"
    },
  )
  Json::object(body)
}

///|
/// Writes the configuration as a document, which is what `dump` is for: a
/// deployment can be read back and checked without the file that produced it.
pub fn Config::dump(self : Config, format~ : Format = Format::Yaml) -> String {
  format.write(self.to_json())
}

///|
/// A span in the shortest form that reads back as the same number of
/// nanoseconds.
pub fn nanos_as_span(nanos : Int64) -> String {
  if nanos == 0L {
    return "0s"
  }
  for
    pair in [
      (604_800_000_000_000L, "w"),
      (86_400_000_000_000L, "d"),
      (3_600_000_000_000L, "h"),
      (60_000_000_000L, "m"),
      (1_000_000_000L, "s"),
      (1_000_000L, "ms"),
      (1_000L, "us"),
    ] {
    if nanos % pair.0 == 0L {
      return (nanos / pair.0).to_string() + pair.1
    }
  }
  nanos.to_string() + "ns"
}
