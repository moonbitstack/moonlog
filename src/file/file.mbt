// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink that appends each entry to a file, rotating it when it grows too
/// large or too old.
///
/// The file is opened on the first write, so a sink that cannot open its file
/// is a failing slot rather than a failure at startup: the health machine puts
/// the sink down, the alarm says why, and a probe retries. `reopen` picks up a
/// file that an outside tool moved away.
///
/// Segments are named `<file>.<20261101T090000>`, or `.gz` too when `compress`
/// is on, and are pruned by `Limits` after every cut. Names are UTC, so a
/// directory listing reads as a history.
pub struct File {
  path : String
  append : Bool
  perms : Int32
  mkdir : Bool
  rotation : Rotation
  limits : Limits
  compress : Bool
  buffer : Int32
  clock : () -> Int64
  mut handle : Int32?
  mut written : Int64
  mut opened : Int64
  held : @buffer.Buffer
}

///|
/// A file sink on `path`.
///
/// `append` keeps what is there (the default) and `false` starts the file
/// empty. `perms` is the mode a new file gets, in the usual octal form. `mkdir`
/// creates the parent directories. `buffer` gathers that many bytes before
/// writing, which trades a lost tail on a crash for fewer calls; 0 writes every
/// line as it arrives.
///
/// `clock` answers nanoseconds since the epoch. A file sink needs one for
/// segment names and time-based rotation, so it reads the system clock unless
/// it is given another.
pub fn File::new(
  path~ : String,
  append~ : Bool = true,
  perms~ : Int32 = 0o644,
  mkdir~ : Bool = false,
  rotation~ : Rotation = Rotation::new(),
  limits~ : Limits = Limits::new(),
  compress~ : Bool = false,
  buffer~ : Int32 = 0,
  clock~ : () -> Int64 = fn() { @env.now().reinterpret_as_int64() * 1_000_000L },
) -> File {
  {
    path,
    append,
    perms,
    mkdir,
    rotation,
    limits,
    compress,
    buffer,
    clock,
    handle: None,
    written: 0L,
    opened: 0L,
    held: @buffer.Buffer::Buffer(),
  }
}

///|
/// The file this sink writes.
pub fn File::path(self : File) -> String {
  self.path
}

///|
/// How many bytes the current file holds.
pub fn File::written(self : File) -> Int64 {
  self.written
}

///|
/// A slot around this sink.
pub fn File::slot(self : File, name~ : String = "file") -> @moonlog.Slot {
  @moonlog.Slot::new(self, name~).kind("file")
}

///|
/// Writes what the buffer holds, then gives the file back to the system. A
/// sink that is buffered should be closed, or its last lines are lost.
pub fn File::close(self : File) -> Unit {
  ignore(self.flush())
  match self.handle {
    Some(fd) => {
      sys_close(fd)
      self.handle = None
    }
    None => ()
  }
}

///|
/// Writes what the buffer holds.
pub fn File::flush(self : File) -> Result[Unit, String] {
  if self.held.is_empty() {
    return Ok(())
  }
  let bytes = self.held.to_bytes()
  self.held.reset()
  match self.open_file() {
    Ok(fd) => self.emit(fd, bytes)
    Err(why) => Err(why)
  }
}

///|
/// Closes the file and opens it again, which is what an outside rotate wants:
/// the old descriptor keeps writing to a file that was moved, this one writes
/// to the path again.
pub fn File::reopen(self : File) -> Result[Unit, String] {
  ignore(self.flush())
  match self.handle {
    Some(fd) => {
      sys_close(fd)
      self.handle = None
    }
    None => ()
  }
  self.opened = (self.clock)()
  match self.open_file() {
    Ok(_) => Ok(())
    Err(why) => Err(why)
  }
}

///|
/// Cuts the file now, whether or not a limit was reached: the current file
/// becomes a segment and a fresh one is started.
pub fn File::rotate(self : File) -> Result[Unit, String] {
  let now = (self.clock)()
  ignore(self.flush())
  match self.handle {
    Some(fd) => sys_close(fd)
    None => ()
  }
  self.handle = None
  let mut cut = None
  if self.written > 0L {
    match self.cut(now) {
      Ok(name) => cut = Some(name)
      Err(why) => return Err(why)
    }
  }
  match self.open_file() {
    Ok(_) => {
      self.written = 0L
      self.opened = now
      match cut {
        Some(_) => {
          self.prune(now)
          Ok(())
        }
        None => Ok(())
      }
    }
    Err(why) => Err(why)
  }
}

///|
/// Moves the current file aside, compressing it when asked.
fn File::cut(self : File, now : Int64) -> Result[String, String] {
  let (dir, base) = split_path(self.path)
  let name = segment(base + "." + stamp(now), sys_list(dir))
  let name = dir + separator(dir) + name
  match sys_rename(self.path, name) {
    Err(why) => return Err(why)
    Ok(_) => ()
  }
  if !self.compress {
    return Ok(name)
  }
  let part = name + ".gz.part"
  let packed = match sys_read(name) {
    Ok(bytes) => @gzip.gzip(bytes)
    Err(why) => return Err(why)
  }
  match sys_open(part, false, self.perms) {
    Ok(fd) => {
      let writable = sys_write(fd, packed)
      sys_close(fd)
      match writable {
        Err(why) => Err(why)
        Ok(_) =>
          match sys_rename(part, name + ".gz") {
            Err(why) => Err(why)
            Ok(_) => {
              ignore(sys_remove(name))
              Ok(name + ".gz")
            }
          }
      }
    }
    Err(why) => Err(why)
  }
}

///|
/// Drops segments the limits no longer allow: the oldest beyond `keep`, the
/// ones older than `max_age`, then the oldest until the rest fit in
/// `max_total`.
///
/// A segment that will not go — another process has it open, most often — is
/// left where it is: the next cut tries again, and failing a rotation over it
/// would lose the line being written.
fn File::prune(self : File, now : Int64) -> Unit {
  if self.limits.keep <= 0 &&
    self.limits.max_age <= 0L &&
    self.limits.max_total <= 0L {
    return
  }
  let segments = self.segments()
  let mut live = segments
  if self.limits.keep > 0 && live.length() > self.limits.keep {
    let surplus = live.length() - self.limits.keep
    for i in 0..<surplus {
      ignore(sys_remove(live[i]))
    }
    live = live[surplus:].to_owned()
  }
  if self.limits.max_age > 0L {
    let kept : Array[String] = []
    for name in live {
      let at = sys_mtime(name)
      if at >= 0L && now - at > self.limits.max_age {
        ignore(sys_remove(name))
      } else {
        kept.push(name)
      }
    }
    live = kept
  }
  if self.limits.max_total > 0L {
    let mut total = 0L
    for name in live {
      total = total + max_of(sys_size(name))
    }
    let mut i = 0
    while total > self.limits.max_total && i < live.length() {
      let size = max_of(sys_size(live[i]))
      ignore(sys_remove(live[i]))
      total = total - size
      i = i + 1
    }
  }
}

///|
/// The segments of this file, oldest first.
///
/// A segment is a file this sink cut and left behind: what a status page lists,
/// and what `keep`, `max_age` and `max_total` count.
pub fn File::segments(self : File) -> Array[String] {
  let (dir, base) = split_path(self.path)
  let prefix = base + "."
  let joined = if dir.has_suffix("/") || dir.has_suffix("\\") {
    dir
  } else {
    dir + separator(dir)
  }
  let names : Array[String] = []
  for name in sys_list(dir) {
    if name.has_prefix(prefix) {
      names.push(joined + name)
    }
  }
  names.sort()
  names
}

///|
/// The separator a directory is joined with, taken from the path that was
/// given: a sink writes the same shape on every platform.
fn separator(dir : String) -> String {
  if dir.contains("\\") && !dir.contains("/") {
    "\\"
  } else {
    "/"
  }
}

///|
/// A size that could not be read counts as nothing to reclaim.
fn max_of(size : Int64) -> Int64 {
  if size < 0L {
    0L
  } else {
    size
  }
}

///|
/// The descriptor, opening the file when it is not open yet.
fn File::open_file(self : File) -> Result[Int32, String] {
  match self.handle {
    Some(fd) => Ok(fd)
    None => {
      if self.mkdir {
        let (dir, _) = split_path(self.path)
        if dir != "." {
          match sys_mkdir(dir) {
            Err(why) => return Err(why)
            Ok(_) => ()
          }
        }
      }
      match sys_open(self.path, self.append, self.perms) {
        Ok(fd) => {
          self.handle = Some(fd)
          self.written = if self.append {
            let size = sys_size(self.path)
            if size < 0L {
              0L
            } else {
              size
            }
          } else {
            0L
          }
          if self.opened == 0L {
            self.opened = (self.clock)()
          }
          Ok(fd)
        }
        Err(why) => Err(why)
      }
    }
  }
}

///|
/// Whether the next line, `incoming` bytes long, should go to a new file.
fn File::due(self : File, now : Int64, incoming : Int64) -> Bool {
  if self.written <= 0L || self.handle is None {
    return false
  }
  let too_big = self.rotation.size > 0L &&
    self.written + incoming > self.rotation.size
  let too_old = self.rotation.every > 0L &&
    now - self.opened >= self.rotation.every
  too_big || too_old
}

///|
/// Writes `bytes` at the end of the file.
fn File::emit(self : File, fd : Int32, bytes : Bytes) -> Result[Unit, String] {
  match sys_write(fd, bytes) {
    Ok(_) => {
      self.written = self.written + bytes.length().to_int64()
      Ok(())
    }
    Err(why) => Err(why)
  }
}

///|
/// Takes one encoded line.
fn File::accept(self : File, bytes : Bytes) -> Result[Unit, String] {
  let now = (self.clock)()
  if self.due(now, bytes.length().to_int64()) {
    match self.rotate() {
      Err(why) => return Err(why)
      Ok(_) => ()
    }
  }
  if self.buffer > 0 {
    self.held.write_bytes(bytes)
    if self.held.length() >= self.buffer {
      return self.flush()
    }
    return Ok(())
  }
  match self.open_file() {
    Ok(fd) => self.emit(fd, bytes)
    Err(why) => Err(why)
  }
}

///|
pub impl @moonlog.Sink for File with fn write(self, entry) {
  self.accept(@utf8.encode(entry.line + "\n"))
}

///|
pub extend File with @moonlog.Sink::{write}
