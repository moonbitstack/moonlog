// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A directory of this run's own, under the temporary directory the system
/// reports, so two test runs do not write over each other.
fn sandbox(name : String) -> String {
  let base = match @env.get_env_var("TMPDIR") {
    Some(dir) => if dir != "" { dir } else { other_temp() }
    None => other_temp()
  }
  let dir = base +
    separator(base) +
    "moonlog-" +
    name +
    "-" +
    @env.now().to_string()
  ignore(sys_mkdir(dir))
  dir
}

///|
fn other_temp() -> String {
  match @env.get_env_var("TEMP") {
    Some(dir) => if dir != "" { dir } else { "." }
    None => "."
  }
}

///|
/// The text of a file, or the empty string when it cannot be read.
fn text_of(path : String) -> String {
  match sys_read(path) {
    Ok(bytes) => @utf8.decode_lossy(bytes)
    Err(_) => ""
  }
}

///|
/// The segments of `path` in `dir`, oldest first, as bare names.
fn segments_of(dir : String, base : String) -> Array[String] {
  let names : Array[String] = []
  for name in sys_list(dir) {
    if name.has_prefix(base + ".") {
      names.push(name)
    }
  }
  names.sort()
  names
}

///|
/// Removes everything under `dir` and the directory itself.
fn sand_out(dir : String) -> Unit {
  for name in sys_list(dir) {
    ignore(sys_remove(dir + separator(dir) + name))
  }
  ignore(sys_remove(dir))
}

///|
/// A hub writing through `file`, with a clock the test moves.
fn hub_writing(file : File, now : Array[Int64]) -> @moonlog.Hub {
  let hub = @moonlog.Hub::new(clock=fn() { now[0] })
  // One slot called `file`, registered once: the name cannot be taken.
  let _ = hub.add(file.slot()) catch { _ => "" }
  hub
}
