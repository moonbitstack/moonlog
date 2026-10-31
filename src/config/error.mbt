// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What went wrong in a configuration file, said in the terms a reader can
/// act on: where in the document, what was there, and what belongs there.
///
/// `at` is a key path such as `slots.file.max_size`, or empty for the document
/// as a whole.
pub(all) suberror Refused {
  Refused(at~ : String, got~ : String, want~ : String)
}

///|
/// A refusal with the key path it happened at.
pub fn Refused::to_text(self : Refused) -> String {
  match self {
    Refused(at~, got~, want~) =>
      if at == "" {
        "got " + got + ", want " + want
      } else {
        "at " + at + ": got " + got + ", want " + want
      }
  }
}

///|
fn refuse(at : String, got : String, want : String) -> Refused {
  Refused(at~, got~, want~)
}

///|
/// A key that is not in the document.
fn missing(at : String, want : String) -> Refused {
  Refused(at~, got="nothing", want~)
}
