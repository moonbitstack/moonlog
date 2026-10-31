// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
extern "C" fn is_terminal(fd : Int32) -> Bool = "moonlog_stdio_is_terminal"

///|
#borrow(bytes)
extern "C" fn write_bytes(fd : Int32, bytes : Bytes) -> Int32 = "moonlog_stdio_write"

///|
/// Writes the encoded line to the descriptor behind `stream`.
fn put_line(
  stream : @moonlog.Stream,
  _line : String,
  bytes : Bytes,
) -> Result[Unit, String] {
  let fd = match stream {
    @moonlog.Stream::Stderr => 2
    _ => 1
  }
  let code = write_bytes(fd, bytes)
  if code == 0 {
    Ok(())
  } else {
    Err("the console refused the line: code " + code.to_string())
  }
}
