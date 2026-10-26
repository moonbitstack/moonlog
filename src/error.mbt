// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A value the library will not take, and why.
///
/// `at` is the offset in the input, counted in characters; `got` is what was
/// there and `want` names what would have been taken. Parsing answers this
/// rather than a default: a configuration file with a typo in it should say so,
/// not run at a verbosity nobody asked for.
pub(all) suberror Refused {
  Refused(at~ : Int32, got~ : String, want~ : String)
}

///|
/// The refusal as one line, for a terminal.
pub fn Refused::to_text(self : Refused) -> String {
  let Refused(at~, got~, want~) = self
  "at " + at.to_string() + ": got `" + got + "`, want " + want
}

///|
/// A refusal at `at`, having found `got` where `want` was expected.
fn refuse(at : Int32, got : String, want : String) -> Refused {
  Refused(at~, got~, want~)
}
