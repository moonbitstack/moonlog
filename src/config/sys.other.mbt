// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// No file system answers on this target: a configuration arrives as text and
/// is parsed, which is the half that does not need one.
let no_file_system : String = "a file needs a native target"

///|
fn sys_read(path : Bytes) -> Result[Bytes, String] {
  Err(no_file_system + ": cannot read " + @utf8.decode_lossy(path))
}

///|
fn sys_write(path : Bytes, _text : Bytes) -> Result[Unit, String] {
  Err(no_file_system + ": cannot write " + @utf8.decode_lossy(path))
}

///|
fn sys_mtime(_path : Bytes) -> Int64 {
  -1L
}
