// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The process-wide hub: a document read once at startup, a logger taken
/// anywhere in the program, and one flush before the process goes away.
///
///     moon run --target native src/examples/08-world
fn main raise {
  let document =
    #|profile: serlog
    #|filter: info, gateway=debug
    #|slots:
    #|  console:
    #|    kind: stdio
    #|    stream: stdout
    #|    layout: "{time:%H:%M:%S} {level:<5} {target}: {msg}{fields}"
  @global.start(config=@config.Config::parse(document))
  let log = @global.logger("gateway")
  log.debug(
    "a debug line, because the filter gives this target its own level",
    fields=[("build", @moonlog.Value::of_str("9f2c1ab"))],
  )
  log.info("serving", fields=[("port", @moonlog.Value::of_int(8080))])
  log.warn("the pool is half empty", fields=[
    ("free", @moonlog.Value::of_int(4)),
  ])
  for status in @global.status() {
    println(
      "slot " +
      status.name +
      " (" +
      status.kind +
      ") is " +
      status.health.name().to_owned(),
    )
  }
  @global.flush()
  @global.shutdown()
}
