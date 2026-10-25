// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One record, every shape this library can give it.
///
///     moon run src/examples/02-formats
fn main raise {
  let scene = @moonlog.Scene::new(
    identity=@moonlog.Identity::of(
      app="mirror",
      env="prod",
      instance="n1",
      host="box-7",
      pid=4242,
    ),
  )
  let record = @moonlog.Record::of(
      @moonlog.warn, "mirror::sync", "disk 91% full",
    )
    .sets([
      ("mirror", @moonlog.Value::of_str("debian")),
      ("id", @moonlog.Value::of_int(7)),
    ])
    .stamped(1_700_000_000_000_000_000L)
    .located("src/sync.mbt", line=12)
    .on("worker-1")

  println("— patterns —")
  let patterns = [
    "serlog", "tracing", "env_logger", "python", "logback", "slog", "pino",
  ]
  for name in patterns {
    println(name + ": " + @moonlog.Pattern::parse(name).render(record, scene))
  }
  println("")
  println("— the same fields, written three ways —")
  println("logfmt: " + @moonlog.Logfmt::new().render(record, scene))
  println("pretty: " + @moonlog.Pretty::new().render(record, scene))
  println("")
  println("— ten JSON schemas —")
  let schemas = [
    @moonlog.Schema::Serlog,
    @moonlog.Schema::Pino,
    @moonlog.Schema::Bunyan,
    @moonlog.Schema::Zap,
    @moonlog.Schema::Slog,
    @moonlog.Schema::Structlog,
    @moonlog.Schema::Logstash,
    @moonlog.Schema::Ecs,
    @moonlog.Schema::Gelf,
    @moonlog.Schema::Otel,
  ]
  for schema in schemas {
    println(
      schema.name() +
      ": " +
      @moonlog.JsonLine::new(schema).render(record, scene),
    )
  }
  println("")
  println("— renamed keys and nested fields —")
  let custom = @moonlog.JsonLine::new(@moonlog.Schema::Serlog)
    .rename("msg", "message")
    .rename("level", "severity")
    .nest("data")
  println(custom.render(record, scene))
  println("")
  println("— a coloured line, for a terminal —")
  println(
    @moonlog.Pattern::parse("{level:<5} {target}: {msg}").render(
      record,
      scene.coloured(true),
    ),
  )
  println("")
  println("— filters —")
  let filter = @moonlog.Filter::parse(
    "info, mirror::sync=debug, mirror::net=off, noisy",
  )
  for
    (level, target) in [
      (@moonlog.debug, "mirror::sync"),
      (@moonlog.debug, "mirror::net"),
      (@moonlog.info, "other"),
      (@moonlog.trace, "noisy::x"),
    ] {
    let verdict = if filter.allows(level, target) {
      "passes"
    } else {
      "dropped"
    }
    println(level.name() + " from " + target + " " + verdict)
  }
}
