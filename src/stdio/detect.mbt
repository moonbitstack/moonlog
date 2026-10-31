// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Whether a slot writing to `stream` should carry escapes.
///
/// `Auto` asks for both streams, so a run whose log is piped into a file gets
/// plain lines even though its failures still reach the terminal.
pub fn terminal(stream : @moonlog.Stream) -> Bool {
  let dumb = match @env.get_env_var("TERM") {
    Some(term) => term == "dumb"
    None => false
  }
  if dumb {
    return false
  }
  match stream {
    @moonlog.Stream::Stdout => is_terminal(1)
    @moonlog.Stream::Stderr => is_terminal(2)
    @moonlog.Stream::Auto => is_terminal(1) && is_terminal(2)
  }
}

///|
/// Whether `NO_COLOR` is set to anything but the empty string, which is what
/// the convention at no-color.org asks for.
pub fn no_color() -> Bool {
  match @env.get_env_var("NO_COLOR") {
    Some(value) => value != ""
    None => false
  }
}

///|
/// `FORCE_COLOR`, when it says something: `0` and `false` turn colour off, any
/// other value turns it on, and an unset variable says nothing.
pub fn force_color() -> Bool? {
  match @env.get_env_var("FORCE_COLOR") {
    Some("0") | Some("false") => Some(false)
    Some(_) => Some(true)
    None => None
  }
}

///|
/// Whether colour is wanted, given what the terminal said and what the
/// environment said.
///
/// `FORCE_COLOR` is the last word — someone who set it meant it — then
/// `NO_COLOR`, then the terminal.
pub fn decide(terminal : Bool, no_color : Bool, force_color : Bool?) -> Bool {
  match force_color {
    Some(wanted) => wanted
    None => if no_color { false } else { terminal }
  }
}
