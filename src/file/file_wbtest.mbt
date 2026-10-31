// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "split path keeps the root and names the file" {
  assert_eq(split_path("/var/log/app.log"), ("/var/log", "app.log"))
  assert_eq(split_path("/app.log"), ("/", "app.log"))
  assert_eq(split_path("app.log"), (".", "app.log"))
  assert_eq(split_path("C:\\logs\\app.log"), ("C:\\logs", "app.log"))
  assert_eq(split_path("C:\\app.log"), ("C:\\", "app.log"))
}

///|
test "a segment is named after the instant it was cut, and never twice the same" {
  let base = "app.log." + stamp(1_700_000_000_000_000_000L)
  assert_eq(base, "app.log.20231114T221320")
  assert_eq(segment(base, []), base)
  assert_eq(segment(base, ["other.log", base]), base + "-001")
  // The sequence continues past the highest one there, so a pruned number is
  // never handed out again and the listing still reads as a history.
  assert_eq(segment(base, [base + "-001", base + "-002"]), base + "-003")
  assert_eq(segment(base, [base + "-002", base + "-002.gz"]), base + "-003")
}

///|
test "rotation and limits answer a copy, so a preset can be shared" {
  let plain = Rotation::new()
  assert_eq(plain.size, 0L)
  assert_eq(plain.every, 0L)
  let sized = plain.size(1024L)
  assert_eq(sized.size, 1024L)
  assert_eq(plain.size, 0L)
  let timed = sized.every(60_000_000_000L)
  assert_eq(timed.size, 1024L)
  assert_eq(timed.every, 60_000_000_000L)
  let limits = Limits::new()
    .keep(3)
    .max_age(86_400_000_000_000L)
    .max_total(1_048_576L)
  assert_eq(limits.keep, 3)
  assert_eq(limits.max_age, 86_400_000_000_000L)
  assert_eq(limits.max_total, 1_048_576L)
}

///|
#cfg(target="native")
test "every line reaches the file, buffered or not" {
  let dir = sandbox("plain")
  let path = dir + separator(dir) + "app.log"
  let now = [1_700_000_000_000_000_000L]
  let direct = File::new(path~, clock=fn() { now[0] })
  let hub = hub_writing(direct, now)
  hub.logger("app").info("first")
  assert_true(sys_size(path) > 0L)
  assert_true(text_of(path).contains("first"))
  direct.close()

  let buffered = File::new(path=path + ".buf", buffer=4096, clock=fn() {
    now[0]
  })
  let hub2 = hub_writing(buffered, now)
  hub2.logger("app").warn("held")
  assert_eq(sys_size(path + ".buf"), -1L)
  buffered.close()
  assert_true(text_of(path + ".buf").contains("held"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "a size limit cuts the file before the line that would cross it" {
  let dir = sandbox("size")
  let base = "app.log"
  let path = dir + separator(dir) + base
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, rotation=Rotation::new(size=40L), clock=fn() {
    now[0]
  })
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  log.info("alpha")
  log.info("beta")
  log.info("gamma")
  file.close()
  let segments = segments_of(dir, base)
  assert_eq(segments.length(), 2)
  assert_true(text_of(dir + separator(dir) + segments[0]).contains("alpha"))
  assert_true(text_of(dir + separator(dir) + segments[1]).contains("beta"))
  let current = text_of(path)
  assert_true(current.contains("gamma"))
  assert_false(current.contains("alpha"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "a time limit cuts the file on the clock it was given" {
  let dir = sandbox("every")
  let base = "app.log"
  let path = dir + separator(dir) + base
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, rotation=Rotation::new(every=60_000_000_000L), clock=fn() {
    now[0]
  })
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  log.info("before")
  now[0] = now[0] + 30_000_000_000L
  log.info("still before")
  assert_eq(segments_of(dir, base).length(), 0)
  now[0] = now[0] + 31_000_000_000L
  log.info("after")
  file.close()
  assert_eq(segments_of(dir, base).length(), 1)
  assert_true(text_of(path).contains("after"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "keep drops the oldest segments" {
  let dir = sandbox("keep")
  let base = "app.log"
  let path = dir + separator(dir) + base
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(
    path~,
    rotation=Rotation::new(size=40L),
    limits=Limits::new().keep(2),
    clock=fn() { now[0] },
  )
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  for word in ["one", "two", "three", "four", "five"] {
    log.info(word)
  }
  file.close()
  let segments = segments_of(dir, base)
  assert_eq(segments.length(), 2)
  assert_false(text_of(dir + separator(dir) + segments[0]).contains("one"))
  assert_true(text_of(dir + separator(dir) + segments[1]).contains("four"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "max age drops what the clock has outrun" {
  let dir = sandbox("age")
  let base = "app.log"
  let path = dir + separator(dir) + base
  // The age of a segment is read off the file, so this one starts at the real
  // instant and then jumps a year.
  let now = [@env.now().reinterpret_as_int64() * 1_000_000L]
  let file = File::new(
    path~,
    rotation=Rotation::new(size=40L),
    limits=Limits::new().max_age(86_400_000_000_000L),
    clock=fn() { now[0] },
  )
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  log.info("one")
  log.info("two")
  assert_eq(segments_of(dir, base).length(), 1)
  // A year on, the segment on disk is older than the limit allows.
  now[0] = now[0] + 365L * 86_400_000_000_000L
  log.info("three")
  file.close()
  assert_eq(segments_of(dir, base).length(), 0)
  assert_true(text_of(path).contains("three"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "max total drops the oldest until the rest fit" {
  let dir = sandbox("total")
  let base = "app.log"
  let path = dir + separator(dir) + base
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(
    path~,
    rotation=Rotation::new(size=40L),
    limits=Limits::new().max_total(100L),
    clock=fn() { now[0] },
  )
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  for word in ["one", "two", "three", "four"] {
    log.info(word)
  }
  file.close()
  let segments = segments_of(dir, base)
  let mut total = 0L
  for name in segments {
    total = total + sys_size(dir + separator(dir) + name)
  }
  assert_true(total <= 100L)
  assert_eq(segments.length(), 2)
  sand_out(dir)
}

///|
#cfg(target="native")
test "a compressed segment unpacks back to the lines that made it" {
  let dir = sandbox("gzip")
  let base = "app.log"
  let path = dir + separator(dir) + base
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, rotation=Rotation::new(size=40L), compress=true, clock=fn() {
    now[0]
  })
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  log.info("alpha")
  log.info("beta")
  file.close()
  let segments = segments_of(dir, base)
  assert_eq(segments.length(), 1)
  assert_true(segments[0].has_suffix(".gz"))
  let packed = match sys_read(dir + separator(dir) + segments[0]) {
    Ok(bytes) => bytes
    Err(why) => fail(why)
  }
  let plain = @gzip.gunzip(packed) catch {
    error => fail("the segment would not unpack: " + error.to_string())
  }
  assert_true(@utf8.decode_lossy(plain).contains("alpha"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "reopen writes to the path again after something moved the file" {
  let dir = sandbox("reopen")
  let path = dir + separator(dir) + "app.log"
  let moved = dir + separator(dir) + "app.log.moved"
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, clock=fn() { now[0] })
  let hub = hub_writing(file, now)
  let log = hub.logger("app")
  log.info("before")
  match sys_rename(path, moved) {
    Ok(_) => ()
    Err(why) => fail(why)
  }
  log.info("while moved")
  match file.reopen() {
    Ok(_) => ()
    Err(why) => fail(why)
  }
  log.info("after")
  file.close()
  assert_true(text_of(moved).contains("while moved"))
  let fresh = text_of(path)
  assert_true(fresh.contains("after"))
  assert_false(fresh.contains("before"))
  sand_out(dir)
}

///|
#cfg(target="native")
test "a file that cannot be opened is a failure the slot reports, not a crash" {
  let dir = sandbox("fail")
  let path = dir + separator(dir) + "missing" + separator(dir) + "app.log"
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, clock=fn() { now[0] })
  let hub = hub_writing(file, now)
  hub.logger("app").error("nowhere to go")
  let status = hub.status()[0]
  assert_eq(status.health, @moonlog.Health::Down)
  assert_true(status.error is Some(_))
  sand_out(dir)
}

///|
#cfg(target="native")
test "a directory is made when the sink is told to" {
  let dir = sandbox("mkdir")
  let path = dir + separator(dir) + "deep" + separator(dir) + "app.log"
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, mkdir=true, clock=fn() { now[0] })
  let hub = hub_writing(file, now)
  hub.logger("app").info("made it")
  file.close()
  assert_true(text_of(path).contains("made it"))
  let inner = dir + separator(dir) + "deep"
  for name in sys_list(inner) {
    ignore(sys_remove(inner + separator(dir) + name))
  }
  ignore(sys_remove(inner))
  sand_out(dir)
}
