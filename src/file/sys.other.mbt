// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// No file system answers on this target, so a file sink says so rather than
/// pretending to have written anything. The package still compiles, and a
/// program that only formats records does not need it.
let no_file_system : String = "a file needs a native target"

///|
fn sys_open(
  path : String,
  _append : Bool,
  _perms : Int32,
) -> Result[Int32, String] {
  Err(no_file_system + ": cannot open " + path)
}

///|
fn sys_write(_fd : Int32, _bytes : Bytes) -> Result[Unit, String] {
  Err(no_file_system)
}

///|
fn sys_close(_fd : Int32) -> Unit {
  ()
}

///|
fn sys_read(path : String) -> Result[Bytes, String] {
  Err(no_file_system + ": cannot read " + path)
}

///|
fn sys_rename(from : String, _to : String) -> Result[Unit, String] {
  Err(no_file_system + ": cannot rename " + from)
}

///|
fn sys_remove(path : String) -> Result[Unit, String] {
  Err(no_file_system + ": cannot remove " + path)
}

///|
fn sys_mkdir(path : String) -> Result[Unit, String] {
  Err(no_file_system + ": cannot make " + path)
}

///|
fn sys_list(_dir : String) -> Array[String] {
  []
}

///|
fn sys_size(_path : String) -> Int64 {
  -1L
}

///|
fn sys_mtime(_path : String) -> Int64 {
  -1L
}
