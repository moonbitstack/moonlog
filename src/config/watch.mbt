// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Reads a configuration file, taking the format from its extension.
pub fn Config::load(path~ : String) -> Config raise Refused {
  let format = Format::of(path)
  let text = match read_text(path) {
    Ok(text) => text
    Err(why) => raise refuse(path, why, "a file that can be read")
  }
  Config::parse(text, format~)
}

///|
/// Writes the configuration to `path` in the format its extension asks for.
pub fn Config::save(self : Config, path~ : String) -> Unit raise Refused {
  let format = Format::of(path)
  match write_text(path, self.dump(format~)) {
    Ok(_) => ()
    Err(why) => raise refuse(path, why, "a file that can be written")
  }
}

///|
/// A configuration file watched for changes.
///
/// There is no background task here: `poll` asks whether the file on disk is
/// newer than the document that was read, and answers the new one. A program
/// that has a loop calls `poll` from it, which keeps the reload on the same
/// thread as everything else and makes it something a test can step through.
pub struct Watcher {
  path : String
  mut stamp : Int64
  format : Format
  lookup : (String) -> String?
}

///|
/// Starts watching `path`.
pub fn Config::watch(
  path~ : String,
  format? : Format,
  lookup~ : (String) -> String? = fn(name) { @env.get_env_var(name) },
) -> Watcher raise Refused {
  let format = match format {
    Some(format) => format
    None => Format::of(path)
  }
  let stamp = modified_at(path)
  if stamp < 0L {
    raise refuse(path, "nothing", "a file that exists")
  }
  { path, stamp, format, lookup, }
}

///|
/// The file being watched.
pub fn Watcher::path(self : Watcher) -> String {
  self.path
}

///|
/// The newest configuration, when the file has changed since the last answer.
///
/// `Ok(None)` means nothing moved. An `Err` means the file changed and the new
/// one will not do — the caller keeps what it has and decides whether to say so.
pub fn Watcher::poll(self : Watcher) -> Result[Config?, String] {
  let stamp = modified_at(self.path)
  if stamp < 0L || stamp == self.stamp {
    return Ok(None)
  }
  let text = match read_text(self.path) {
    Ok(text) => text
    Err(why) => return Err(why)
  }
  try {
    let config = Config::parse(text, format=self.format, lookup=self.lookup)
    self.stamp = stamp
    Ok(Some(config))
  } catch {
    error => Err(error.to_text())
  }
}
