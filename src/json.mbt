// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A JSON shape other tools already read.
pub(all) enum Schema {
  Serlog
  Pino
  Bunyan
  Zap
  Slog
  Structlog
  Logstash
  Ecs
  Gelf
  Otel
} derive(Eq, Debug)

///|
pub extend Schema with Eq::{equal, not_equal}

///|
pub extend Schema with Debug::{to_repr}

///|
/// The name used in configuration files and vector files.
pub fn Schema::name(self : Schema) -> StringView {
  match self {
    Serlog => "serlog"
    Pino => "pino"
    Bunyan => "bunyan"
    Zap => "zap"
    Slog => "slog"
    Structlog => "structlog"
    Logstash => "logstash"
    Ecs => "ecs"
    Gelf => "gelf"
    Otel => "otel"
  }
}

///|
pub fn Schema::parse(name : StringView) -> Schema raise Refused {
  match name {
    "serlog" => Serlog
    "pino" => Pino
    "bunyan" => Bunyan
    "zap" => Zap
    "slog" => Slog
    "structlog" => Structlog
    "logstash" => Logstash
    "ecs" => Ecs
    "gelf" => Gelf
    "otel" => Otel
    _ => raise refuse(0, name.to_owned(), "a JSON schema name")
  }
}

///|
/// How levels are written, when a schema is told to write them another way.
pub(all) enum Levels {
  Name
  Number
} derive(Eq, Debug)

///|
pub extend Levels with Eq::{equal, not_equal}

///|
pub extend Levels with Debug::{to_repr}

///|
pub fn Levels::parse(name : StringView) -> Levels raise Refused {
  match name {
    "name" => Name
    "number" => Number
    _ => raise refuse(0, name.to_owned(), "name or number")
  }
}

///|
/// One record as a JSON object in a schema, with any key renamed.
pub struct JsonLine {
  schema : Schema
  keys : Array[(String, String)]
  mut levels : Levels?
  mut nest : String?
}

///|
pub fn JsonLine::new(schema : Schema) -> JsonLine {
  { schema, keys: [], levels: None, nest: None, }
}

///|
/// Writes `key` as `to`, such as `msg` as `message`.
pub fn JsonLine::rename(self : JsonLine, key : String, to : String) -> JsonLine {
  self.keys.push((key, to))
  self
}

///|
/// Writes levels by name or by number, whatever the schema does by default.
pub fn JsonLine::levels(self : JsonLine, levels : Levels) -> JsonLine {
  self.levels = Some(levels)
  self
}

///|
/// Puts the fields under one key instead of at the top.
pub fn JsonLine::nest(self : JsonLine, key : String) -> JsonLine {
  self.nest = Some(key)
  self
}

///|
pub impl Layout for JsonLine with fn render(self, record, scene) {
  self.encode(record, scene)
}

///|
pub extend JsonLine with Layout::{render}

///|
/// An object being written, which knows the renamed keys.
priv struct Obj {
  out : StringBuilder
  keys : Array[(String, String)]
  mut first : Bool
}

///|
fn Obj::open(out : StringBuilder, keys : Array[(String, String)]) -> Obj {
  out.write_char('{')
  { out, keys, first: true, }
}

///|
fn Obj::key(self : Obj, name : String) -> Unit {
  if !self.first {
    self.out.write_char(',')
  }
  self.first = false
  let mut written = name
  for (from, to) in self.keys {
    if from == name {
      written = to
    }
  }
  write_json_string(self.out, written)
  self.out.write_char(':')
}

///|
fn quote_open(out : StringBuilder) -> Unit {
  out.write_char('"')
}

///|
fn quote_close(out : StringBuilder) -> Unit {
  out.write_char('"')
}

///|
fn Obj::str(self : Obj, name : String, value : String) -> Unit {
  self.key(name)
  write_json_string(self.out, value)
}

///|
fn Obj::raw(self : Obj, name : String, value : String) -> Unit {
  self.key(name)
  self.out.write_string(value)
}

///|
fn Obj::text(self : Obj, name : String, value : String) -> Unit {
  self.str(name, value)
}

///|
fn Obj::opt(self : Obj, name : String, value : String?) -> Unit {
  match value {
    Some(text) => self.str(name, text)
    None => ()
  }
}

///|
fn Obj::nonempty(self : Obj, name : String, value : String) -> Unit {
  if value.length() > 0 {
    self.str(name, value)
  }
}

///|
fn Obj::close(self : Obj) -> Unit {
  self.out.write_char('}')
}

///|
/// Writes one record as a JSON object.
pub fn JsonLine::encode(
  self : JsonLine,
  record : Record,
  scene : Scene,
) -> String {
  let out = StringBuilder()
  let o = Obj::open(out, self.keys)
  let identity = scene.identity
  let level = record.level
  match self.schema {
    Serlog => {
      o.key("time")
      quote_open(o.out)
      write_iso(o.out, record.time)
      quote_close(o.out)
      self.name_or(o, "level", level)
      o.str("target", record.target)
      o.str("msg", record.msg)
      o.opt("file", record.caller.file)
      match record.caller.line {
        Some(line) => o.raw("line", line.to_string())
        None => ()
      }
      write_object_fields(o, record, "error", self.nest, false)
      o.nonempty("app", identity.app)
      o.nonempty("env", identity.env)
      o.nonempty("instance", identity.instance)
    }
    Pino => {
      match self.levels {
        Some(Name) => o.str("level", level.name())
        _ => o.raw("level", level.value.to_string())
      }
      o.raw("time", floor_div(record.time, 1_000_000L).to_string())
      o.raw("pid", identity.pid.to_string())
      o.text("hostname", identity.host)
      write_object_fields(o, record, "err", self.nest, false)
      o.str("msg", record.msg)
    }
    Bunyan => {
      o.str("name", identity.app)
      o.text("hostname", identity.host)
      o.raw("pid", identity.pid.to_string())
      match self.levels {
        Some(Name) => o.str("level", level.name())
        _ => o.raw("level", level.value.to_string())
      }
      write_object_fields(o, record, "err", self.nest, false)
      o.str("msg", record.msg)
      o.key("time")
      quote_open(o.out)
      write_iso(o.out, record.time)
      quote_close(o.out)
      o.raw("v", "0")
    }
    Zap => {
      self.name_or(o, "level", level)
      o.raw("ts", seconds_with_millis(record.time))
      o.str("logger", record.target)
      o.opt("caller", file_line(record))
      o.str("msg", record.msg)
      write_object_fields(o, record, "error", self.nest, false)
    }
    Slog => {
      o.key("time")
      quote_open(o.out)
      write_strftime(
        o.out,
        record.time,
        (identity.offset)(record.time),
        "%Y-%m-%dT%H:%M:%S%.9f%:z",
      )
      quote_close(o.out)
      self.name_or(o, "level", level.named(label(level, Profile::Slog)))
      o.str("msg", record.msg)
      write_object_fields(o, record, "error", self.nest, false)
    }
    Structlog => {
      o.str("event", record.msg)
      write_object_fields(o, record, "error", self.nest, false)
      self.name_or(o, "level", level)
      o.str("logger", record.target)
      o.key("timestamp")
      quote_open(o.out)
      write_iso(o.out, record.time)
      quote_close(o.out)
    }
    Logstash => {
      o.key("@timestamp")
      quote_open(o.out)
      write_strftime(
        o.out,
        record.time,
        (identity.offset)(record.time),
        "%Y-%m-%dT%H:%M:%S%.3f%:z",
      )
      quote_close(o.out)
      o.str("@version", "1")
      o.str("message", record.msg)
      o.str("logger_name", record.target)
      o.opt("thread_name", record.thread)
      self.name_or(o, "level", level.named(label(level, Profile::Logback)))
      o.raw("level_value", level.logstash().to_string())
      write_object_fields(o, record, "stack_trace", self.nest, false)
    }
    Ecs => {
      o.key("@timestamp")
      quote_open(o.out)
      write_iso(o.out, record.time)
      quote_close(o.out)
      self.name_or(o, "log.level", level)
      o.str("message", record.msg)
      o.str("ecs.version", "8.11.0")
      o.str("log.logger", record.target)
      o.opt("log.origin.file.name", record.caller.file)
      match record.caller.line {
        Some(line) => o.raw("log.origin.file.line", line.to_string())
        None => ()
      }
      o.raw("process.pid", identity.pid.to_string())
      o.text("host.hostname", identity.host)
      o.nonempty("service.name", identity.app)
      o.nonempty("service.environment", identity.env)
      o.nonempty("service.node.name", identity.instance)
      write_object_fields(o, record, "error", self.nest, false)
    }
    Gelf => {
      o.str("version", "1.1")
      o.text("host", identity.host)
      o.str("short_message", record.msg)
      o.raw("timestamp", seconds_with_millis(record.time))
      o.raw("level", level.syslog().to_string())
      o.str("_target", record.target)
      write_object_fields(o, record, "error", self.nest, true)
    }
    Otel => {
      o.key("timestamp")
      quote_open(o.out)
      write_iso_nanos(o.out, record.time)
      quote_close(o.out)
      o.str("severity_text", label(level, Profile::Serlog))
      o.raw("severity_number", level.otel().to_string())
      o.str("body", record.msg)
      o.key("attributes")
      let attrs = Obj::open(o.out, self.keys)
      attrs.str("code.namespace", record.target)
      attrs.opt("code.filepath", record.caller.file)
      match record.caller.line {
        Some(line) => attrs.raw("code.lineno", line.to_string())
        None => ()
      }
      for pair in record.fields {
        attrs.key(pair.0)
        pair.1.write_json(attrs.out)
      }
      attrs.close()
      o.key("resource")
      let resource = Obj::open(o.out, self.keys)
      resource.nonempty("service.name", identity.app)
      resource.nonempty("deployment.environment", identity.env)
      resource.nonempty("service.instance.id", identity.instance)
      resource.close()
    }
  }
  o.close()
  out.to_string()
}

///|
/// Writes the level as its name or its number, whichever the layout was told.
fn JsonLine::name_or(
  self : JsonLine,
  o : Obj,
  key : String,
  level : Level,
) -> Unit {
  match self.levels {
    Some(Number) => o.raw(key, level.value.to_string())
    _ => o.str(key, level.name())
  }
}

///|
/// How a profile's logger writes a level, as a name.
fn label(level : Level, profile : Profile) -> String {
  level.label(profile)
}

///|
fn file_line(record : Record) -> String? {
  match record.caller.file {
    Some(file) =>
      match record.caller.line {
        Some(line) => Some(file + ":" + line.to_string())
        None => Some(file)
      }
    None => None
  }
}

///|
/// Seconds since the epoch with three decimals, as zap's `ts` and GELF's
/// `timestamp` want.
fn seconds_with_millis(time : Int64) -> String {
  let seconds = floor_div(time, 1_000_000_000L)
  let millis = floor_div(time - seconds * 1_000_000_000L, 1_000_000L)
  let out = StringBuilder()
  out.write_string(seconds.to_string())
  out.write_char('.')
  write_digits(out, millis.to_int(), 3)
  out.to_string()
}

///|
/// The fields, under `nest` when the layout was told to nest them; a field
/// called `error` is written under `error_key`, and `id` is left out of a GELF
/// document, which reserves it.
fn write_object_fields(
  o : Obj,
  record : Record,
  error_key : String,
  nest : String?,
  prefixed : Bool,
) -> Unit {
  if record.fields.length() == 0 {
    return
  }
  match nest {
    Some(key) => {
      o.key(key)
      let inner = Obj::open(o.out, o.keys)
      each_field(inner, record, error_key, prefixed)
      inner.close()
    }
    None => each_field(o, record, error_key, prefixed)
  }
}

///|
fn each_field(
  o : Obj,
  record : Record,
  error_key : String,
  prefixed : Bool,
) -> Unit {
  for (name, value) in record.fields {
    if prefixed && name == "id" {
      continue
    }
    let key = if name == "error" { error_key } else { name }
    if prefixed {
      o.key("_" + key)
    } else {
      o.key(key)
    }
    value.write_json(o.out)
  }
}
