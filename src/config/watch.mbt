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
/// There is no background task here: `poll` reads the file and answers it when
/// the bytes differ from the last document it saw, which keeps the reload on
/// the same thread as everything else and makes it something a test can step
/// through. Comparing content — rather than the modification time — means a
/// rewrite is never missed because two edits landed inside one timestamp tick,
/// which is the usual way a fast test (or a coarse filesystem clock) fools an
/// mtime check. A configuration document is small, so reading it on each poll
/// is cheap; parsing happens only when the content actually moved.
pub struct Watcher {
  path : String
  mut seen : String
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
  let text = match read_text(path) {
    Ok(text) => text
    Err(why) => raise refuse(path, why, "a file that can be read")
  }
  { path, seen : text, format, lookup, }
}

///|
/// The file being watched.
pub fn Watcher::path(self : Watcher) -> String {
  self.path
}

///|
/// The newest configuration, when the file has changed since the last answer.
///
/// `Ok(None)` means the bytes are unchanged. An `Err` means the file changed
/// and the new one will not do — the caller keeps what it has and decides
/// whether to say so.
pub fn Watcher::poll(self : Watcher) -> Result[Config?, String] {
  let text = match read_text(self.path) {
    Ok(text) => text
    Err(why) => return Err(why)
  }
  if text == self.seen {
    return Ok(None)
  }
  try {
    let config = Config::parse(text, format=self.format, lookup=self.lookup)
    self.seen = text
    Ok(Some(config))
  } catch {
    error => Err(error.to_text())
  }
}
