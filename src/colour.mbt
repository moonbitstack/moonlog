// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A colour a terminal understands.
///
/// `Alarm` is white on red, which is what a fatal line is worth. `Plain` writes
/// no escape at all, so a value that never reached a terminal is unchanged.
pub(all) enum Colour {
  Plain
  Red
  Green
  Yellow
  Blue
  Magenta
  Cyan
  White
  Grey
  Alarm
} derive(Eq, Debug)

///|
pub extend Colour with Debug::{to_repr}

///|
pub extend Colour with Eq::{equal, not_equal}

///|
/// The escape that starts this colour, empty for `Plain`.
pub fn Colour::ansi(self : Colour) -> String {
  match self {
    Plain => ""
    Red => "\u{1b}[1;31m"
    Green => "\u{1b}[32m"
    Yellow => "\u{1b}[33m"
    Blue => "\u{1b}[34m"
    Magenta => "\u{1b}[35m"
    Cyan => "\u{1b}[36m"
    White => "\u{1b}[37m"
    Grey => "\u{1b}[90m"
    Alarm => "\u{1b}[1;37;41m"
  }
}

///|
/// The name used in configuration, filters and vector files.
pub fn Colour::name(self : Colour) -> StringView {
  match self {
    Plain => "plain"
    Red => "red"
    Green => "green"
    Yellow => "yellow"
    Blue => "blue"
    Magenta => "magenta"
    Cyan => "cyan"
    White => "white"
    Grey => "grey"
    Alarm => "alarm"
  }
}

///|
/// A colour by name, `gray` included, which is how American spelling arrives.
pub fn Colour::parse(name : StringView) -> Colour raise Refused {
  match name {
    "plain" => Plain
    "red" => Red
    "green" => Green
    "yellow" => Yellow
    "blue" => Blue
    "magenta" => Magenta
    "cyan" => Cyan
    "white" => White
    "grey" | "gray" => Grey
    "alarm" => Alarm
    _ => raise refuse(0, name.to_owned(), "a colour name")
  }
}

///|
/// The escape that ends every colour.
pub let reset : String = "\u{1b}[0m"
