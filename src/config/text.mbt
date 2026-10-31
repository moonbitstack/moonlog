// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A file as text. The bytes and the string are traded here so that a target
/// without a file system only has to say so once.
fn read_text(path : String) -> Result[String, String] {
  match sys_read(@utf8.encode(path)) {
    Ok(bytes) => Ok(@utf8.decode_lossy(bytes))
    Err(why) => Err(why)
  }
}

///|
fn write_text(path : String, text : String) -> Result[Unit, String] {
  sys_write(@utf8.encode(path), @utf8.encode(text))
}
