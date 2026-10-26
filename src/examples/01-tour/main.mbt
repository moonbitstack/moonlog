// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole surface in one run: a hub, two slots, a filter, a pattern, a
/// processor and a logger with a field bound to it.
///
///     moon run src/examples/01-tour
fn main raise {
  let sink = @moonlog.Memory::new()
  let hub = @moonlog.Hub::new(
    identity=@moonlog.Identity::of(app="mirror", env="prod", instance="n1"),
    clock=fn() { 1_700_000_000_000_000_000L },
    filter=@moonlog.Filter::parse("info,mirror::sync=debug"),
  )
  let pattern = @moonlog.Pattern::parse(
    "{time:%H:%M:%S%.3f} {level:<5} {target}: {msg}{fields}",
  )
  let slot = @moonlog.Slot::new(sink, name="console").layout(pattern)
  let _ = hub.add(slot)

  // A logger holds a target and a field; every line carries both.
  let log = hub
    .logger("mirror::sync")
    .bound("run", @moonlog.Value::of_str("2026-10-25"))
  log.info("starting", fields=[("workers", @moonlog.Value::of_int(4))])
  log.debug("scanning", fields=[("path", @moonlog.Value::of_str("/srv/mirror"))])
  log.warn("slow", fields=[("took_ms", @moonlog.Value::of_int(1200))])

  // A filter keeps targets it was not told about at `info`.
  hub.logger("other").debug("not shown")
  hub.logger("other").error("shown")

  // Reading it back is reading the sink.
  for line in sink.lines() {
    println(line)
  }

  // The same record in six shapes.
  let record = @moonlog.Record::of(
      @moonlog.warn, "mirror::sync", "disk 91% full",
    )
    .sets([
      ("mirror", @moonlog.Value::of_str("debian")),
      ("free_gb", @moonlog.Value::of_float(1.5)),
    ])
    .stamped(1_700_000_000_000_000_000L)
  let scene = hub.scene()
  println("")
  println("pattern  " + @moonlog.Pattern::parse("serlog").render(record, scene))
  println("logfmt   " + @moonlog.Logfmt::new().render(record, scene))
  println("pretty   " + @moonlog.Pretty::new().render(record, scene))
  println(
    "json     " +
    @moonlog.JsonLine::new(@moonlog.Schema::Serlog).render(record, scene),
  )
  println(
    "ecs      " +
    @moonlog.JsonLine::new(@moonlog.Schema::Ecs).render(record, scene),
  )
  println(
    "otel     " +
    @moonlog.JsonLine::new(@moonlog.Schema::Otel).render(record, scene),
  )
}
