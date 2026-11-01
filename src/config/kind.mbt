// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink of your own that a document can name: what `kind` it answers to, the keys it reads beside
/// the ones every slot has, and how to make it from the slot once the document is read.
///
/// A name a built-in kind has is refused: a document that says `file` should not change meaning
/// with what the program passed in.
pub(all) struct Kind {
  name : String
  keys : Array[String]
  build : (Slot) -> &@moonlog.Sink raise Refused
}

///|
/// A kind called `name`, built by `build`, whose keys are checked for being there and no more: the
/// shape of each is for `build` to judge, through `Slot::text` and the rest.
pub fn Kind::new(
  name : String,
  build : (Slot) -> &@moonlog.Sink raise Refused,
  keys? : Array[String],
) -> Kind {
  { name, keys: keys.unwrap_or([]), build, }
}

///|
/// The kinds passed to `parse`, refusing one that takes a built-in name, or a name twice.
fn checked(kinds : Array[Kind]) -> Unit raise Refused {
  for i, kind in kinds {
    if settings_of(kind.name) is Some(_) ||
      kinds[:i].iter().any(k => k.name == kind.name) {
      raise refuse("kinds", "`" + kind.name + "`", "a name not already taken")
    }
  }
}

///|
/// The kind a document's `kind` names among the program's own.
fn own(kinds : Array[Kind], name : String) -> Kind? {
  kinds.iter().find_first(k => k.name == name)
}

///|
/// A kind's keys as settings, any shape allowed.
fn loose(kind : Kind) -> Array[(String, Setting)] {
  kind.keys.map(key => (key, Setting::Any))
}

///|
/// The sink the program's own kind makes for `slot`, or `None` when the slot is a built-in kind.
pub fn Config::build(
  self : Config,
  slot : Slot,
) -> &@moonlog.Sink? raise Refused {
  match own(self.kinds, slot.kind) {
    Some(kind) => Some((kind.build)(slot))
    None => None
  }
}
