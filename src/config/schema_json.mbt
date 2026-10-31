// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The JSON Schema a document of this shape answers to.
///
/// It is built from the same tables the parser checks against, so the schema an
/// editor or a pipeline validates with cannot drift from the parser: a key the
/// schema allows is a key the parser reads, and a value of the wrong shape is
/// refused in both places. Publish it next to a deployment for the editor to
/// pick up; `moonlog/config` never needs it to read a file.
pub fn Config::schema() -> Json {
  let properties : Map[String, Json] = Map([])
  properties["profile"] = object([
    ("type", text("string")),
    ("enum", array(profiles().map(fn(name) { text(name) }))),
  ])
  properties["filter"] = object([("type", text("string"))])
  properties["alarm"] = alarm_schema()
  properties["slots"] = object([
    ("type", text("object")),
    ("additionalProperties", object([("oneOf", array(kinds.map(kind_schema)))])),
  ])
  object([
    ("$schema", text("https://json-schema.org/draft/2020-12/schema")),
    ("title", text("moonlog configuration")),
    ("type", text("object")),
    ("additionalProperties", json_bool(false)),
    ("properties", Json::object(properties)),
    (
      "anyOf",
      array([
        object([("required", array([text("filter")]))]),
        object([("required", array([text("slots")]))]),
      ]),
    ),
  ])
}

///|
/// The schema of one kind of slot: the keys it reads, and the ones it cannot do
/// without.
fn kind_schema(kind : (String, Array[(String, Setting)])) -> Json {
  let properties : Map[String, Json] = Map([])
  properties["kind"] = object([("const", text(kind.0))])
  for pair in common {
    properties[pair.0] = setting_schema(pair.1)
  }
  properties["queue"] = queue_schema()
  for pair in kind.1 {
    properties[pair.0] = setting_schema(pair.1)
  }
  let required : Array[Json] = [text("kind")]
  for name in required_of(kind.0) {
    required.push(text(name))
  }
  object([
    ("type", text("object")),
    ("additionalProperties", json_bool(false)),
    ("properties", Json::object(properties)),
    ("required", array(required)),
  ])
}

///|
/// The settings a kind cannot do without.
fn required_of(kind : String) -> Array[String] {
  match kind {
    "file" => ["path"]
    "loki" => ["url"]
    "mail" => ["host", "from", "to"]
    _ => []
  }
}

///|
/// The schema of a queue.
fn queue_schema() -> Json {
  let properties : Map[String, Json] = Map([])
  properties["size"] = object([("type", text("number"))])
  properties["batch"] = object([("type", text("number"))])
  properties["wait"] = object([("type", text("string"))])
  properties["full"] = object([
    ("type", text("string")),
    ("enum", array([text("drop"), text("block")])),
  ])
  object([
    ("type", text("object")),
    ("additionalProperties", json_bool(false)),
    ("properties", Json::object(properties)),
    ("required", array([text("size")])),
  ])
}

///|
/// The schema of an alarm.
fn alarm_schema() -> Json {
  let properties : Map[String, Json] = Map([])
  properties["tiers"] = object([
    ("type", text("array")),
    (
      "items",
      object([
        ("type", text("array")),
        ("items", object([("type", text("string"))])),
      ]),
    ),
    ("minItems", Json::number(1.0)),
  ])
  properties["remind"] = object([("type", text("string"))])
  properties["fallback"] = object([
    ("type", text("string")),
    ("enum", array([text("ignore"), text("panic")])),
  ])
  object([
    ("type", text("object")),
    ("additionalProperties", json_bool(false)),
    ("properties", Json::object(properties)),
    ("required", array([text("tiers")])),
  ])
}

///|
/// The schema of one setting, from the shape the parser checks for.
fn setting_schema(setting : Setting) -> Json {
  match setting {
    Text => object([("type", text("string"))])
    Flag => object([("type", text("boolean"))])
    Count => object([("type", text("number"))])
    Size => object([("type", array([text("string"), text("number")]))])
    Span => object([("type", text("string"))])
    Texts =>
      object([
        ("type", text("array")),
        ("items", object([("type", text("string"))])),
      ])
    Pairs =>
      object([
        ("type", text("object")),
        ("additionalProperties", object([("type", text("string"))])),
      ])
  }
}

///|
/// The seven profile names, in the order they are declared.
fn profiles() -> Array[String] {
  ["serlog", "tracing", "env_logger", "python", "logback", "slog", "pino"]
}

///|
/// A JSON string.
fn text(value : String) -> Json {
  Json::string(value)
}

///|
/// A JSON true or false.
fn json_bool(value : Bool) -> Json {
  Json::boolean(value)
}

///|
/// A JSON array of values.
fn array(values : Array[Json]) -> Json {
  Json::array(values)
}

///|
/// A JSON object, with its keys in the order they are written here.
fn object(pairs : Array[(String, Json)]) -> Json {
  let entries : Map[String, Json] = Map([])
  for pair in pairs {
    entries[pair.0] = pair.1
  }
  Json::object(entries)
}
