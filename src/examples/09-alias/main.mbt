// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The package under the name the other implementations use.
///
/// The shared specification, and the five implementations of it, are called
/// `serlog`; this is the MoonBit one, and `moon.pkg` hands it to this file as
/// `@serlog`. Every item below is the item `@moonlog` would give — the name a
/// file is written with is a reading choice, not a second API, so a reader of
/// the Go or the Rust implementation recognises the lines.
///
///     moon run src/examples/09-alias
fn main raise {
  let sink = @serlog.Memory::new()
  let hub = @serlog.Hub::new(
    identity=@serlog.Identity::of(app="mirror", env="prod", instance="n1"),
    clock=fn() { 1_700_000_000_000_000_000L },
  )
  let _ = hub.add(
    @serlog.Slot::new(sink, name="console").layout(
      @serlog.Pattern::parse(
        "{time:%H:%M:%S%.3f} {level:<5} {target}: {msg}{fields}",
      ),
    ),
  )
  // The logger, the level constants and the value constructors are the ones
  // this package already had, written with the name the other five use.
  let log = hub.logger("mirror::sync")
  log.info("starting", fields=[("workers", @serlog.Value::of_int(4))])
  log.warn("slow", fields=[("took_ms", @serlog.Value::of_int(1200))])

  for line in sink.lines() {
    println(line)
  }
}
