// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The three shapes a configuration file is written in. All three read into
/// the same tree, so the same document means the same configuration whichever
/// one it is written in.
pub(all) enum Format {
  Yaml
  Json
  Toml
}

///|
/// A format by name.
pub fn Format::parse(name : StringView) -> Format raise Refused {
  match name {
    "yaml" | "yml" => Yaml
    "json" => Json
    "toml" => Toml
    _ => raise refuse("", name.to_owned(), "a format: yaml, json or toml")
  }
}

///|
/// The format a file name asks for, by its extension.
pub fn Format::of(path : StringView) -> Format raise Refused {
  let name = match path.rev_find(".") {
    Some(at) => path[at + 1:]
    None =>
      raise refuse(
        "".to_string(),
        path.to_owned(),
        "a name with an extension: .yaml, .json or .toml",
      )
  }
  Format::parse(name)
}

///|
/// The name this format is written as.
pub fn Format::name(self : Format) -> StringView {
  match self {
    Yaml => "yaml"
    Json => "json"
    Toml => "toml"
  }
}

///|
/// Reads a document into the tree every reader in this family produces.
pub fn Format::read(
  self : Format,
  text : StringView,
  at : String,
) -> Json raise Refused {
  let tree = try {
    match self {
      Json => @moonjson.loads(text, @moonjson.strict)
      Yaml =>
        @moonyaml.loads(text, flavor=@moonyaml.strict, schema=@moonyaml.core)
      Toml => @moontoml.loads(text, flavor=@moontoml.strict)
    }
  } catch {
    error => raise refuse(at, error.to_string(), "a document that parses")
  }
  tree
}

///|
/// Writes the tree back out in this format.
pub fn Format::write(self : Format, tree : Json) -> String {
  match self {
    Json => @moonjson.dumps(tree, indent=2, sort=true)
    Yaml => @moonyaml.dumps(tree, indent=2, sort=true)
    Toml => @moontoml.dumps(tree, sort=true)
  }
}
