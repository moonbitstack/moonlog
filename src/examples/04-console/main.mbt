// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Three consoles: one on standard output, one on standard error, and one that
/// chooses per record. The last part shows what the colour decision comes to
/// when there is no terminal to ask.
///
///     moon run src/examples/04-console
fn main raise {
  for
    stream in [
      @moonlog.Stream::Stdout,
      @moonlog.Stream::Stderr,
      @moonlog.Stream::Auto,
    ] {
    let console = @stdio.Console::new(stream~, colour=false)
    println(
      "a console on " +
      console.stream().name().to_owned() +
      " sends info to " +
      console.target(@moonlog.info).name().to_owned() +
      " and error to " +
      console.target(@moonlog.error).name().to_owned(),
    )
  }
  println(
    "colour: wanted " +
    @stdio.decide(true, false, None).to_string() +
    " on a terminal, " +
    @stdio.decide(false, false, None).to_string() +
    " in a pipe, " +
    @stdio.decide(true, true, None).to_string() +
    " with NO_COLOR, " +
    @stdio.decide(false, true, Some(true)).to_string() +
    " with FORCE_COLOR",
  )
  let hub = @moonlog.Hub::new(clock=fn() { 1_700_000_000_000_000_000L })
  let coloured = @stdio.Console::new(
    stream=@moonlog.Stream::Stdout,
    colour=true,
  )
  ignore(hub.add(coloured.slot()))
  let log = hub.logger("queue")
  log.info("drained", fields=[("took_ms", @moonlog.Value::of_int(12))])
  log.warn("backing up", fields=[("depth", @moonlog.Value::of_int(4096))])
  log.error("refused a writer")
}
