// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The document the shared specification writes, read into the same `Config`
/// the shorter spelling of this package reads.
///
/// Two spellings of one model: `sinks` is a list whose entries carry their own
/// `kind`, `alarms` is a table of named alarms a sink's `on_fail` points at,
/// and `compat` names the profile. Everything a deployment can say is here,
/// because a document written for the specification is the one an operator
/// already has.
///
/// | specification | here |
/// |:--|:--|
/// | `compat` | `profile` |
/// | `app`, `env`, `instance` | the identity a record carries |
/// | `level`, `filter`, `filter_env` | the filter in force |
/// | `levels` | levels a filter or a slot may name |
/// | `process`, `redact` | the chain every record walks |
/// | `sinks` | the slots |
/// | `alarms` | the alarm a sink's `on_fail` names, and the default |
/// | `watch` | how often the file is checked |
fn spec_of(
  root : Map[String, Json],
  lookup : (String) -> String?,
) -> Config raise Refused {
  let config = Config::new()
  // Levels are read before anything that may name one.
  match root.get("levels") {
    Some(value) => config.levels = levels_of(value)
    None => ()
  }
  let mut sinks = None
  let mut alarms = None
  let mut steps = None
  let mut redacted = None
  for key, value in root {
    match key {
      "app" => config.app = word(key, value)
      "env" => config.env = word(key, value)
      "instance" => config.instance = word(key, value)
      "compat" => config.profile = profile_of(key, value)
      "level" => config.filter = level_named(key, value, config.levels)
      "filter" =>
        config.filter = levels_named(
          substitute(key, value, lookup),
          config.levels,
        )
      "filter_env" => config.filter_env = Some(word(key, value))
      "levels" => ()
      "process" => steps = Some(value)
      "redact" => redacted = Some(value)
      "sinks" => sinks = Some(value)
      "alarms" => alarms = Some(value)
      "watch" => config.watch = Some(parse_span(key, word(key, value)))
      _ =>
        raise refuse(
          key,
          "a key",
          "app, env, instance, compat, level, filter, filter_env, levels, " +
          "process, redact, sinks, alarms or watch",
        )
    }
  }
  // The chain is `process` first and the `redact` shorthand after it, in that
  // order whatever order the document happens to write them in: a table has no
  // order to keep.
  build_chain(config, steps, redacted)
  match alarms {
    Some(value) => config.alarms = alarms_of(value, lookup)
    None => ()
  }
  for pair in config.alarms {
    if pair.0 == "default" {
      config.alarm = Some(pair.1)
    }
  }
  match sinks {
    Some(value) => config.slots = spec_sinks(value, config.levels, lookup)
    None => ()
  }
  // A named alarm a sink points at has to be one the document defines.
  for slot in config.slots {
    match slot.on_fail {
      Some(name) =>
        if name != "panic" && name != "ignore" && name != "default" {
          let mut found = false
          for pair in config.alarms {
            if pair.0 == name {
              found = true
            }
          }
          if !found {
            raise refuse(
              "sinks." + slot.name + ".on_fail",
              "`" + name + "`",
              "panic, ignore, default, or an alarm the document defines",
            )
          }
        }
      None => ()
    }
  }
  config
}

///|
/// The deployment's own name, as the document gives it.
pub fn Config::app(self : Config) -> String {
  self.app
}

///|
/// The environment the deployment calls itself part of.
pub fn Config::env(self : Config) -> String {
  self.env
}

///|
/// The node within that environment.
pub fn Config::instance(self : Config) -> String {
  self.instance
}

///|
/// The levels the document defines, in the order it defines them.
pub fn Config::levels(self : Config) -> Array[@moonlog.Level] {
  self.levels
}

///|
/// The chain every record walks before a slot sees it.
pub fn Config::chain(self : Config) -> Array[&@moonlog.Processor] {
  self.chain
}

///|
/// The chain's steps as the document wrote them, which is what `dump` writes
/// back.
pub fn Config::process(self : Config) -> Array[Json] {
  self.process
}

///|
/// The alarms the document names, each with the name a sink points at.
pub fn Config::alarms(self : Config) -> Array[(String, Alarm)] {
  self.alarms
}

///|
/// How often the document asks for its file to be checked, in nanoseconds.
///
/// Named `watch_span` because `Config::watch` is the watcher this package hands
/// back for a file.
pub fn Config::watch_span(self : Config) -> Int64? {
  self.watch
}

///|
/// The variable whose value overrides the filter, when the document names one.
pub fn Config::filter_env(self : Config) -> String? {
  self.filter_env
}

///|
/// The chain a document asks for: `process` first, then the `redact` shorthand,
/// and the steps as written kept for `dump` to write back.
fn build_chain(
  config : Config,
  steps : Json?,
  redacted : Json?,
) -> Unit raise Refused {
  match steps {
    Some(value) => {
      let items = match as_list(value) {
        Some(items) => items
        None => raise refuse("process", shown(value), "a list of steps")
      }
      config.chain = chain_of("process", value, config.levels)
      for item in items {
        config.process.push(item)
      }
    }
    None => ()
  }
  match redacted {
    Some(value) => {
      config.chain.push(redact_step("redact", value, shorthand=true))
      let step : Map[String, Json] = Map([])
      step["redact"] = value
      config.process.push(Json::object(step))
    }
    None => ()
  }
}

///|
/// A string, or a refusal that names where it should have been.
fn word(at : String, value : Json) -> String raise Refused {
  match as_text(value) {
    Some(text) => text
    None => raise refuse(at, shown(value), "a string")
  }
}

///|
/// A level as a document writes it: a name this package knows, a name the
/// document defined, or a number.
fn level_named(
  at : String,
  value : Json,
  levels : Array[@moonlog.Level],
) -> String raise Refused {
  let text = match value {
    Number(_, ..) =>
      match as_count(value) {
        Some(number) => number.to_int().to_string()
        None => word(at, value)
      }
    _ => word(at, value)
  }
  for level in levels {
    if level.name == text {
      return level.value.to_string()
    }
  }
  ignore(
    @moonlog.Level::parse(text) catch {
      _ =>
        raise refuse(
          at,
          "`" + text + "`",
          "a level name, a number from 0 to 255, or a level the document defines",
        )
    },
  )
  text
}

///|
/// The levels a document defines: a value, or a value and a colour.
fn levels_of(value : Json) -> Array[@moonlog.Level] raise Refused {
  let table = match as_table(value) {
    Some(table) => table
    None => raise refuse("levels", shown(value), "a table of levels")
  }
  let levels : Array[@moonlog.Level] = []
  for name, body in table {
    let at = "levels." + name
    if name != name.to_lower() || name.contains(" ") {
      raise refuse(at, "`" + name + "`", "a lower-case name")
    }
    let (value, colour) = match body {
      Object(_) => {
        let fields = match as_table(body) {
          Some(fields) => fields
          None => raise refuse(at, shown(body), "a value and a colour")
        }
        let number = match fields.get("value") {
          Some(value) =>
            match as_count(value) {
              Some(number) => number.to_int()
              None => raise refuse(at + ".value", shown(value), "a number")
            }
          None => raise missing(at + ".value", "the level's value")
        }
        let colour = match fields.get("colour") {
          Some(value) =>
            match as_text(value) {
              Some(text) =>
                @moonlog.Colour::parse(text) catch {
                  _ =>
                    raise refuse(at + ".colour", "`" + text + "`", "a colour")
                }
              None => raise refuse(at + ".colour", shown(value), "a colour")
            }
          None => @moonlog.Colour::Plain
        }
        for key, _ in fields {
          if key != "value" && key != "colour" {
            raise refuse(at + "." + key, "a key", "value or colour")
          }
        }
        (number, colour)
      }
      _ =>
        match as_count(body) {
          Some(number) => (number.to_int(), @moonlog.Colour::Plain)
          None =>
            raise refuse(at, shown(body), "a number, or a value and a colour")
        }
    }
    if value < 0 || value > 255 {
      raise refuse(at, value.to_string(), "a number from 0 to 255")
    }
    levels.push({ name, value, colour, })
  }
  levels
}

///|
/// The `process` chain: one step per entry, each either a name or a table of
/// one name and its options.
fn chain_of(
  at : String,
  value : Json,
  levels : Array[@moonlog.Level],
) -> Array[&@moonlog.Processor] raise Refused {
  let items = match as_list(value) {
    Some(items) => items
    None => raise refuse(at, shown(value), "a list of steps")
  }
  let chain : Array[&@moonlog.Processor] = []
  for index, item in items {
    chain.push(step_of(at + "." + index.to_string(), item, levels))
  }
  chain
}

///|
/// One step of a chain.
fn step_of(
  at : String,
  item : Json,
  levels : Array[@moonlog.Level],
) -> &@moonlog.Processor raise Refused {
  let (name, options) = match item {
    String(name) => (name, None)
    Object(_) => {
      let table = match as_table(item) {
        Some(table) => table
        None => raise refuse(at, shown(item), "a step")
      }
      if table.length() != 1 {
        raise refuse(at, "a table", "one step: a name and its options")
      }
      let mut name = ""
      let mut options = None
      for key, body in table {
        name = key
        options = Some(body)
      }
      (name, options)
    }
    _ => raise refuse(at, shown(item), "a step")
  }
  match name {
    "sanitise" => {
      let step : &@moonlog.Processor = @moonlog.Sanitise::new()
      step
    }
    "redact" =>
      redact_step(at + "." + name, options.unwrap_or(Json::object(Map([]))))
    "fields" => fields_step(at + "." + name, options)
    "match" => {
      let step : &@moonlog.Processor = condition_of(
        at + "." + name,
        options,
        levels,
        true,
      )
      step
    }
    "exclude" => {
      let step : &@moonlog.Processor = condition_of(
        at + "." + name,
        options,
        levels,
        false,
      )
      step
    }
    "sample" => sample_step(at + "." + name, options)
    "limit" => limit_step(at + "." + name, options)
    "dedupe" => dedupe_step(at + "." + name, options)
    _ =>
      raise refuse(
        at,
        "`" + name + "`",
        "redact, sanitise, fields, match, exclude, sample, limit or dedupe",
      )
  }
}

///|
/// `redact`: a list of top-level keys (the shorthand) or a table of options.
fn redact_step(
  at : String,
  options : Json,
  shorthand? : Bool,
) -> &@moonlog.Processor raise Refused {
  let shorthand = shorthand.unwrap_or(false)
  let mut step = @moonlog.Redact::new()
  match options {
    String(key) => step = step.key(key)
    Array(items) =>
      for item in items {
        step = step.key(word(at, item))
      }
    // The shorthand at the top of a document is a list of keys; the options
    // belong to a `redact` step, so a table is refused there rather than read
    // as keys.
    Object(_) if shorthand => {
      let table = match as_table(options) {
        Some(table) => table
        None => raise refuse(at, shown(options), "a table of options")
      }
      for key, body in table {
        match key {
          "keys" =>
            for item in spec_names(at + ".keys", body) {
              step = step.key(item)
            }
          "paths" =>
            for item in spec_names(at + ".paths", body) {
              step = step.path(item)
            }
          "patterns" =>
            for item in spec_names(at + ".patterns", body) {
              step = step.pattern(item) catch {
                _ =>
                  raise refuse(at + ".patterns", "`" + item + "`", "a pattern")
              }
            }
          "mask" => step = step.mask(word(at + ".mask", body))
          _ =>
            raise refuse(
              at + "." + key,
              "a key",
              "keys, paths, patterns or mask",
            )
        }
      }
    }
    _ => raise refuse(at, shown(options), "a key or a list of keys")
  }
  let done : &@moonlog.Processor = step
  done
}

///|
/// A name, or a list of them.
fn spec_names(at : String, value : Json) -> Array[String] raise Refused {
  match value {
    String(name) => [name]
    Array(items) => {
      let out : Array[String] = []
      for item in items {
        out.push(word(at, item))
      }
      out
    }
    _ => raise refuse(at, shown(value), "a name or a list of names")
  }
}

///|
/// `fields`: the values every record carries.
fn fields_step(
  at : String,
  options : Json?,
) -> &@moonlog.Processor raise Refused {
  let table = match options {
    Some(value) =>
      match as_table(value) {
        Some(table) => table
        None => raise refuse(at, shown(value), "a table of values")
      }
    None => raise refuse(at, "nothing", "a table of values")
  }
  let mut step = @moonlog.Fields::new()
  for key, value in table {
    step = step.set(key, value_of(value))
  }
  let done : &@moonlog.Processor = step
  done
}

///|
/// `match` and `exclude`: the conditions a record has to meet to be kept or
/// dropped.
fn condition_of(
  at : String,
  options : Json?,
  levels : Array[@moonlog.Level],
  keeps : Bool,
) -> &@moonlog.Processor raise Refused {
  let table = match options {
    Some(value) =>
      match as_table(value) {
        Some(table) => table
        None => raise refuse(at, shown(value), "a table of conditions")
      }
    None => raise refuse(at, "nothing", "a table of conditions")
  }
  let mut keep = @moonlog.Keep::new()
  for key, value in table {
    match key {
      "tags" =>
        for tag in spec_names(at + ".tags", value) {
          keep = keep.tag(tag)
        }
      "fields" => {
        let pairs = match as_table(value) {
          Some(pairs) => pairs
          None =>
            raise refuse(at + ".fields", shown(value), "a table of values")
        }
        for name, item in pairs {
          keep = keep.field(name, value_of(item).to_text())
        }
      }
      "level" => {
        let name = level_named(at + ".level", value, levels)
        let level = @moonlog.Level::parse(name) catch {
          _ => raise refuse(at + ".level", "`" + name + "`", "a level")
        }
        keep = keep.level(level)
      }
      _ => raise refuse(at + "." + key, "a key", "tags, fields or level")
    }
  }
  if keeps {
    let step : &@moonlog.Processor = keep
    step
  } else {
    exclude_like(at, table, levels)
  }
}

///|
/// The same table read as an `exclude`, which drops what meets it.
fn exclude_like(
  at : String,
  table : Map[String, Json],
  levels : Array[@moonlog.Level],
) -> &@moonlog.Processor raise Refused {
  let mut step = @moonlog.Exclude::new()
  for key, value in table {
    match key {
      "tags" =>
        for tag in spec_names(at + ".tags", value) {
          step = step.tag(tag)
        }
      "fields" => {
        let pairs = match as_table(value) {
          Some(pairs) => pairs
          None =>
            raise refuse(at + ".fields", shown(value), "a table of values")
        }
        for name, item in pairs {
          step = step.field(name, value_of(item).to_text())
        }
      }
      "level" => {
        let name = level_named(at + ".level", value, levels)
        let level = @moonlog.Level::parse(name) catch {
          _ => raise refuse(at + ".level", "`" + name + "`", "a level")
        }
        step = step.level(level)
      }
      _ => raise refuse(at + "." + key, "a key", "tags, fields or level")
    }
  }
  let done : &@moonlog.Processor = step
  done
}

///|
/// `sample`: the first few of a window, then one every so often.
fn sample_step(
  at : String,
  options : Json?,
) -> &@moonlog.Processor raise Refused {
  let table = match options {
    Some(value) =>
      match as_table(value) {
        Some(table) => table
        None => raise refuse(at, shown(value), "a table of options")
      }
    None => Map([])
  }
  // A hundred of a burst, then one in a hundred, a second at a time: the
  // defaults every implementation of the specification uses.
  let mut first = 100
  let mut every = 100
  let mut per = 1_000_000_000L
  for key, value in table {
    match key {
      "first" =>
        first = match as_count(value) {
          Some(number) => number.to_int()
          None => raise refuse(at + ".first", shown(value), "a number")
        }
      "every" =>
        every = match as_count(value) {
          Some(number) => number.to_int()
          None => raise refuse(at + ".every", shown(value), "a number")
        }
      "per" => per = parse_span(at + ".per", word(at + ".per", value))
      _ => raise refuse(at + "." + key, "a key", "first, every or per")
    }
  }
  let step : &@moonlog.Processor = @moonlog.Sample::new(first~, every~, per~)
  step
}

///|
/// `limit`: a token bucket.
fn limit_step(
  at : String,
  options : Json?,
) -> &@moonlog.Processor raise Refused {
  let table = match options {
    Some(value) =>
      match as_table(value) {
        Some(table) => table
        None => raise refuse(at, shown(value), "a table of options")
      }
    None => raise refuse(at, "nothing", "a rate")
  }
  let mut rate = -1.0
  let mut burst = -1.0
  for key, value in table {
    match key {
      "rate" =>
        rate = match as_count(value) {
          Some(number) => number
          None => raise refuse(at + ".rate", shown(value), "a number")
        }
      "burst" =>
        burst = match as_count(value) {
          Some(number) => number
          None => raise refuse(at + ".burst", shown(value), "a number")
        }
      _ => raise refuse(at + "." + key, "a key", "rate or burst")
    }
  }
  if rate < 0.0 {
    raise missing(at + ".rate", "how many records a second go through")
  }
  // A bucket holds a second's worth unless the document says otherwise.
  if burst < 0.0 {
    burst = rate
  }
  let step : &@moonlog.Processor = @moonlog.Limit::new(rate~, burst~)
  step
}

///|
/// `dedupe`: one record per level, target and message in a window.
fn dedupe_step(
  at : String,
  options : Json?,
) -> &@moonlog.Processor raise Refused {
  let table = match options {
    Some(value) =>
      match as_table(value) {
        Some(table) => table
        None => raise refuse(at, shown(value), "a table of options")
      }
    None => Map([])
  }
  let mut within = 1_000_000_000L
  for key, value in table {
    match key {
      "within" =>
        within = parse_span(at + ".within", word(at + ".within", value))
      _ => raise refuse(at + "." + key, "a key", "within")
    }
  }
  let step : &@moonlog.Processor = @moonlog.Dedupe::new(within~)
  step
}

///|
/// A field value as the document wrote it: the same shapes a record carries.
fn value_of(value : Json) -> @moonlog.Value {
  match value {
    Null => @moonlog.Value::Null
    True => @moonlog.Value::of_bool(true)
    False => @moonlog.Value::of_bool(false)
    Number(number, ..) =>
      if number == number.to_int().to_double() {
        @moonlog.Value::of_long(number.to_int64())
      } else {
        @moonlog.Value::of_float(number)
      }
    String(text) => @moonlog.Value::of_str(text)
    Array(items) => {
      let out : Array[@moonlog.Value] = []
      for item in items {
        out.push(value_of(item))
      }
      @moonlog.Value::of_list(out)
    }
    Object(entries) => {
      let out : Array[(String, @moonlog.Value)] = []
      for key, item in entries {
        out.push((key, value_of(item)))
      }
      @moonlog.Value::of_map(out)
    }
  }
}

///|
/// The named alarms a document defines.
fn alarms_of(
  value : Json,
  lookup : (String) -> String?,
) -> Array[(String, Alarm)] raise Refused {
  let table = match as_table(value) {
    Some(table) => table
    None => raise refuse("alarms", shown(value), "a table of named alarms")
  }
  let alarms : Array[(String, Alarm)] = []
  for name, body in table {
    if name == "panic" || name == "ignore" {
      raise refuse(
        "alarms." + name,
        "`" + name + "`",
        "a name that is not a fallback",
      )
    }
    let fields = match as_table(body) {
      Some(fields) => fields
      None => raise refuse("alarms." + name, shown(body), "a table")
    }
    for key, _ in fields {
      if key != "kind" && key != "tiers" && key != "on_fail" && key != "remind" {
        raise refuse(
          "alarms." + name + "." + key,
          "a key",
          "kind, tiers, on_fail or remind",
        )
      }
    }
    match fields.get("kind") {
      Some(kind) =>
        match as_text(kind) {
          Some(kind) =>
            if kind != "tiers" {
              raise refuse(
                "alarms." + name + ".kind",
                "`" + kind + "`",
                "tiers",
              )
            }
          None =>
            raise refuse("alarms." + name + ".kind", shown(kind), "a string")
        }
      None => ()
    }
    // The specification calls an alarm's fallback `on_fail`; the reader this
    // package already had calls it `fallback`.
    let translated : Map[String, Json] = Map([])
    for key, value in fields {
      match key {
        "on_fail" => translated["fallback"] = value
        _ => translated[key] = value
      }
    }
    alarms.push((name, alarm_of(Json::object(translated), lookup)))
  }
  alarms
}

///|
/// The sinks a document lists, in the order it lists them, each with the name
/// it gave or the one its kind and number make.
fn spec_sinks(
  value : Json,
  levels : Array[@moonlog.Level],
  lookup : (String) -> String?,
) -> Array[Slot] raise Refused {
  let items = match as_list(value) {
    Some(items) => items
    None => raise refuse("sinks", shown(value), "a list of sinks")
  }
  let seen : Array[String] = []
  let counts : Map[String, Int32] = Map([])
  let slots : Array[Slot] = []
  for index, item in items {
    let at = "sinks." + index.to_string()
    let fields = match as_table(item) {
      Some(fields) => fields
      None => raise refuse(at, shown(item), "a table with a kind")
    }
    let kind = match fields.get("kind") {
      Some(value) => word(at + ".kind", value)
      None => raise missing(at + ".kind", "the kind of sink this is")
    }
    let name = match fields.get("name") {
      Some(value) => word(at + ".name", value)
      None => {
        // `kind-n`, counting per kind and skipping names the document already
        // took, so a sink called `file-1` only pushes the next one to `file-2`.
        let mut number = match counts.get(kind) {
          Some(count) => count
          None => 0
        }
        let mut chosen = ""
        while chosen == "" {
          number = number + 1
          let candidate = kind + "-" + number.to_string()
          if !seen.contains(candidate) {
            chosen = candidate
          }
        }
        counts[kind] = number
        chosen
      }
    }
    if name == "*" {
      raise refuse(at + ".name", "`*`", "a name no other sink has")
    }
    if seen.contains(name) {
      raise refuse(at + ".name", "`" + name + "`", "a name no other sink has")
    }
    seen.push(name)
    let translated = spec_sink_table(at, kind, fields)
    let slot = slot_of(name, translated, lookup, at~, levels~)
    // A slot's own level or filter may name a level the document defined.
    match slot.filter {
      Some(spec) =>
        for level in levels {
          if spec == level.name {
            slot.filter = Some(level.value.to_string())
          }
        }
      None => ()
    }
    match fields.get("on_fail") {
      Some(value) => slot.on_fail = Some(word(at + ".on_fail", value))
      None => ()
    }
    match fields.get("alarm_only") {
      Some(value) =>
        match as_flag(value) {
          Some(flag) => slot.alarm_only = flag
          None =>
            raise refuse(at + ".alarm_only", shown(value), "true or false")
        }
      None => ()
    }
    slots.push(slot)
  }
  slots
}

///|
/// A sink as the specification writes it, in the spelling the rest of this
/// package reads: `console` is the console this package calls `stdio`, `gzip`
/// is `compress`, `rotate` is `every`, and `user` and `pass` are the same pair
/// as `username` and `password`.
fn spec_sink_table(
  at : String,
  kind : String,
  fields : Map[String, Json],
) -> Json raise Refused {
  let out : Map[String, Json] = Map([])
  let mut format = None
  let mut pattern = None
  let mut schema = None
  for key, value in fields {
    match key {
      "name" | "on_fail" | "alarm_only" | "kind" => ()
      "gzip" => out["compress"] = value
      "user" => out["username"] = value
      "pass" => out["password"] = value
      "rotate" => {
        let name = word(at + ".rotate", value)
        let span = match name {
          "minute" => 60_000_000_000L
          "hour" => 3_600_000_000_000L
          "day" => 86_400_000_000_000L
          "week" => 604_800_000_000_000L
          _ =>
            raise refuse(
              at + ".rotate",
              "`" + name + "`",
              "minute, hour, day or week",
            )
        }
        out["every"] = Json::string(nanos_as_span(span))
      }
      "format" => format = Some(word(at + ".format", value))
      "pattern" => pattern = Some(word(at + ".pattern", value))
      "schema" => schema = Some(word(at + ".schema", value))
      "colours" =>
        raise refuse(
          at + ".colours",
          "a table",
          "one colour for every level; this package colours a whole slot",
        )
      "keys" | "nest" =>
        raise refuse(
          at + "." + key,
          "a key",
          "a layout this package cannot name: `format`, `pattern` or `schema`",
        )
      "connect" =>
        raise refuse(
          at + ".connect",
          "a start-up check",
          "a check this package does not run: a sink starts on its first write",
        )
      "roll_name" | "reopen" | "flush_every" =>
        raise refuse(
          at + "." + key,
          "a key",
          "a file setting this package does not read yet",
        )
      "perms" =>
        match as_text(value) {
          Some(text) => {
            let digits = if text.has_prefix("0o") {
              text[2:].to_owned()
            } else if text.has_prefix("0") {
              text[1:].to_owned()
            } else {
              text
            }
            let mut mode = 0
            for digit in digits.to_array() {
              if digit < '0' || digit > '7' {
                raise refuse(
                  at + ".perms",
                  "`" + text + "`",
                  "a file mode written in octal, such as 0640",
                )
              }
              mode = mode * 8 + (digit.to_int() - '0'.to_int())
            }
            out["perms"] = Json::number(mode.to_double())
          }
          None => out[key] = value
        }
      _ => out[key] = value
    }
  }
  // The kind stays the word the document used: it is what a status page and
  // an alarm name a sink by, so renaming it here would report a sink the
  // operator never asked for. `console` is the console this package also
  // calls `stdio`.
  out["kind"] = Json::string(kind)
  // `format` names the shape, `pattern` and `schema` fill it in; a `pattern`
  // or a `schema` on its own says which shape it must be.
  let layout = match format {
    Some("logfmt") => Some("logfmt")
    Some("pretty") => Some("pretty")
    Some("json") =>
      match schema {
        Some(schema) => Some("json:" + schema)
        None => Some("json")
      }
    Some("text") | None =>
      match (pattern, schema) {
        (Some(pattern), _) => Some(pattern)
        (None, Some(schema)) => Some("json:" + schema)
        (None, None) => None
      }
    Some(name) =>
      raise refuse(
        at + ".format",
        "`" + name + "`",
        "text, logfmt, json or pretty",
      )
  }
  match layout {
    Some(layout) => out["layout"] = Json::string(layout)
    None => ()
  }
  Json::object(out)
}
