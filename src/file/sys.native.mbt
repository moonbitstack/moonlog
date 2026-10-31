// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
#borrow(path)
extern "C" fn open_ffi(path : Bytes, append : Bool, perms : Int32) -> Int32 = "moonlog_file_open"

///|
#borrow(bytes)
extern "C" fn write_ffi(fd : Int32, bytes : Bytes) -> Int32 = "moonlog_file_write"

///|
extern "C" fn close_ffi(fd : Int32) = "moonlog_file_close"

///|
extern "C" fn error_ffi(code : Int32) -> Bytes = "moonlog_file_error"

///|
#borrow(path)
extern "C" fn read_ffi(path : Bytes) -> Bytes = "moonlog_file_read"

///|
#borrow(from, to)
extern "C" fn rename_ffi(from : Bytes, to : Bytes) -> Int32 = "moonlog_file_rename"

///|
#borrow(path)
extern "C" fn remove_ffi(path : Bytes) -> Int32 = "moonlog_file_remove"

///|
#borrow(path)
extern "C" fn mkdir_ffi(path : Bytes) -> Int32 = "moonlog_file_mkdir"

///|
#borrow(dir)
extern "C" fn list_ffi(dir : Bytes) -> Bytes = "moonlog_file_list"

///|
#borrow(path)
extern "C" fn size_ffi(path : Bytes) -> Int64 = "moonlog_file_size"

///|
#borrow(path)
extern "C" fn mtime_ffi(path : Bytes) -> Int64 = "moonlog_file_mtime"

///|
/// The system's own words for an errno.
fn reason(code : Int32) -> String {
  @utf8.decode_lossy(error_ffi(code))
}

///|
/// A failure with what was being done and what the system said.
fn failed(what : String, code : Int32) -> String {
  what + ": " + reason(code)
}

///|
/// Opens the file, creating it, and answers the descriptor.
fn sys_open(
  path : String,
  append : Bool,
  perms : Int32,
) -> Result[Int32, String] {
  let fd = open_ffi(@utf8.encode(path), append, perms)
  if fd < 0 {
    Err(failed("cannot open " + path, -fd))
  } else {
    Ok(fd)
  }
}

///|
fn sys_write(fd : Int32, bytes : Bytes) -> Result[Unit, String] {
  let code = write_ffi(fd, bytes)
  if code == 0 {
    Ok(())
  } else {
    Err(failed("cannot write", code))
  }
}

///|
fn sys_close(fd : Int32) -> Unit {
  close_ffi(fd)
}

///|
/// The whole file, or an error when it could not all be read.
fn sys_read(path : String) -> Result[Bytes, String] {
  let bytes = read_ffi(@utf8.encode(path))
  let want = size_ffi(@utf8.encode(path))
  if want < 0L {
    return Err("cannot read " + path)
  }
  if bytes.length().to_int64() != want {
    return Err("cannot read all of " + path)
  }
  Ok(bytes)
}

///|
fn sys_rename(from : String, to : String) -> Result[Unit, String] {
  let code = rename_ffi(@utf8.encode(from), @utf8.encode(to))
  if code == 0 {
    Ok(())
  } else {
    Err(failed("cannot rename " + from, code))
  }
}

///|
fn sys_remove(path : String) -> Result[Unit, String] {
  let code = remove_ffi(@utf8.encode(path))
  if code == 0 {
    Ok(())
  } else {
    Err(failed("cannot remove " + path, code))
  }
}

///|
fn sys_mkdir(path : String) -> Result[Unit, String] {
  let code = mkdir_ffi(@utf8.encode(path))
  if code == 0 {
    Ok(())
  } else {
    Err(failed("cannot make " + path, code))
  }
}

///|
fn sys_list(dir : String) -> Array[String] {
  let names : Array[String] = []
  for name in @utf8.decode_lossy(list_ffi(@utf8.encode(dir))).split("\n") {
    if name != "" {
      names.push(name.to_owned())
    }
  }
  names
}

///|
fn sys_size(path : String) -> Int64 {
  size_ffi(@utf8.encode(path))
}

///|
fn sys_mtime(path : String) -> Int64 {
  mtime_ffi(@utf8.encode(path))
}
