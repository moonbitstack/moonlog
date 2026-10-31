// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A file sink cutting itself into segments: two kilobytes each, compressed as
/// they are cut, three of them kept.
///
///     moon run --target native src/examples/05-file
fn main raise {
  let now = [1_700_000_000_000_000_000L]
  let base = match @env.get_env_var("TMPDIR") {
    Some(dir) => if dir == "" { "." } else { dir }
    None =>
      match @env.get_env_var("TEMP") {
        Some(dir) => dir
        None => "."
      }
  }
  let joiner = if base.contains("\\") { "\\" } else { "/" }
  let path = base +
    joiner +
    "moonlog-example-" +
    @env.now().to_string() +
    joiner +
    "gateway.log"
  println("writing to " + path)
  let file = @file.File::new(
    path~,
    mkdir=true,
    rotation=@file.Rotation::new(size=2_048L),
    limits=@file.Limits::new(keep=3),
    compress=true,
    clock=fn() { now[0] },
  )
  let hub = @moonlog.Hub::new(clock=fn() { now[0] })
  ignore(hub.add(file.slot()))
  let log = hub.logger("gateway")
  for i in 0..<40 {
    log.info("a request came in", fields=[
      ("n", @moonlog.Value::of_int(i)),
      ("path", @moonlog.Value::of_str("/api/items/heading")),
    ])
    now[0] = now[0] + 1_000_000_000L
  }
  file.close()
  println(
    "the file being written holds " + file.written().to_string() + " bytes",
  )
  let segments = file.segments()
  println("cut " + segments.length().to_string() + " segments, three kept:")
  for segment in segments {
    println("  " + segment)
  }
}
