// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Nothing here answers on a file descriptor, so nothing is a terminal.
fn is_terminal(_fd : Int32) -> Bool {
  false
}

///|
/// Prints the line through the host's own output, which is `console.log` on
/// JavaScript and the runner's capture on WebAssembly.
fn put_line(
  stream : @moonlog.Stream,
  line : String,
  _bytes : Bytes,
) -> Result[Unit, String] {
  match stream {
    @moonlog.Stream::Stderr => eprintln(line)
    _ => println(line)
  }
  Ok(())
}
