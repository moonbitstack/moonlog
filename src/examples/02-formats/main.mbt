// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One record, every shape this library can give it.
///
///     moon run src/examples/02-formats
fn main raise {
  let scene = @log.Scene::new(
    identity=@log.Identity::of(
      app="mirror",
      env="prod",
      instance="n1",
      host="box-7",
      pid=4242,
    ),
  )
  let record = @log.Record::of(@log.warn, "mirror::sync", "disk 91% full")
    .sets([
      ("mirror", @log.Value::of_str("debian")),
      ("id", @log.Value::of_int(7)),
    ])
    .stamped(1_700_000_000_000_000_000L)
    .located("src/sync.mbt", line=12)
    .on("worker-1")

  println("— patterns —")
  let patterns = [
    "serlog", "tracing", "env_logger", "python", "logback", "slog", "pino",
  ]
  for name in patterns {
    println(name + ": " + @log.Pattern::parse(name).render(record, scene))
  }
  println("")
  println("— the same fields, written three ways —")
  println("logfmt: " + @log.Logfmt::new().render(record, scene))
  println("pretty: " + @log.Pretty::new().render(record, scene))
  println("")
  println("— ten JSON schemas —")
  let schemas = [
    @log.Schema::Serlog,
    @log.Schema::Pino,
    @log.Schema::Bunyan,
    @log.Schema::Zap,
    @log.Schema::Slog,
    @log.Schema::Structlog,
    @log.Schema::Logstash,
    @log.Schema::Ecs,
    @log.Schema::Gelf,
    @log.Schema::Otel,
  ]
  for schema in schemas {
    println(
      schema.name() + ": " + @log.JsonLine::new(schema).render(record, scene),
    )
  }
  println("")
  println("— renamed keys and nested fields —")
  let custom = @log.JsonLine::new(@log.Schema::Serlog)
    .rename("msg", "message")
    .rename("level", "severity")
    .nest("data")
  println(custom.render(record, scene))
  println("")
  println("— a coloured line, for a terminal —")
  println(
    @log.Pattern::parse("{level:<5} {target}: {msg}").render(
      record,
      scene.coloured(true),
    ),
  )
  println("")
  println("— filters —")
  let filter = @log.Filter::parse(
    "info, mirror::sync=debug, mirror::net=off, noisy",
  )
  for
    (level, target) in [
      (@log.debug, "mirror::sync"),
      (@log.debug, "mirror::net"),
      (@log.info, "other"),
      (@log.trace, "noisy::x"),
    ] {
    let verdict = if filter.allows(level, target) {
      "passes"
    } else {
      "dropped"
    }
    println(level.name() + " from " + target + " " + verdict)
  }
}
