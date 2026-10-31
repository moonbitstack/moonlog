// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
#borrow(path)
extern "C" fn read_ffi(path : Bytes) -> Bytes = "moonlog_config_read"

///|
#borrow(path, text)
extern "C" fn write_ffi(path : Bytes, text : Bytes) -> Int32 = "moonlog_config_write"

///|
#borrow(path)
extern "C" fn mtime_ffi(path : Bytes) -> Int64 = "moonlog_config_mtime"

///|
/// The whole file, as bytes.
fn sys_read(path : Bytes) -> Result[Bytes, String] {
  let at = mtime_ffi(path)
  if at < 0L {
    return Err("cannot read " + @utf8.decode_lossy(path))
  }
  Ok(read_ffi(path))
}

///|
/// Replaces the file with `text`.
fn sys_write(path : Bytes, text : Bytes) -> Result[Unit, String] {
  let code = write_ffi(path, text)
  if code == 0 {
    Ok(())
  } else {
    Err("cannot write " + @utf8.decode_lossy(path))
  }
}

///|
/// When the file last changed, in nanoseconds; -1 when it cannot be read.
fn sys_mtime(path : Bytes) -> Int64 {
  mtime_ffi(path)
}
