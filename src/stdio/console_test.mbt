// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "colour: an explicit answer, then FORCE_COLOR, then NO_COLOR, then the terminal" {
  assert_true(@stdio.decide(true, false, None))
  assert_false(@stdio.decide(false, false, None))
  assert_false(@stdio.decide(true, true, None))
  assert_true(@stdio.decide(false, false, Some(true)))
  assert_false(@stdio.decide(true, false, Some(false)))
  assert_false(@stdio.decide(true, true, Some(false)))
  assert_true(@stdio.decide(false, true, Some(true)))
}

///|
test "NO_COLOR counts only when it is set to something" {
  @env.unset_env_var("NO_COLOR")
  assert_false(@stdio.no_color())
  @env.set_env_var("NO_COLOR", "")
  assert_false(@stdio.no_color())
  @env.set_env_var("NO_COLOR", "1")
  assert_true(@stdio.no_color())
  @env.unset_env_var("NO_COLOR")
}

///|
test "FORCE_COLOR reads 0 and false as off and anything else as on" {
  @env.unset_env_var("FORCE_COLOR")
  assert_eq(@stdio.force_color(), None)
  @env.set_env_var("FORCE_COLOR", "0")
  assert_eq(@stdio.force_color(), Some(false))
  @env.set_env_var("FORCE_COLOR", "false")
  assert_eq(@stdio.force_color(), Some(false))
  @env.set_env_var("FORCE_COLOR", "3")
  assert_eq(@stdio.force_color(), Some(true))
  @env.unset_env_var("FORCE_COLOR")
}

///|
test "an auto console sends error and above to standard error" {
  let console = @stdio.Console::new(stream=@moonlog.Stream::Auto, colour=false)
  assert_eq(console.target(@moonlog.trace), @moonlog.Stream::Stdout)
  assert_eq(console.target(@moonlog.info), @moonlog.Stream::Stdout)
  assert_eq(console.target(@moonlog.warn), @moonlog.Stream::Stdout)
  assert_eq(console.target(@moonlog.error), @moonlog.Stream::Stderr)
  assert_eq(console.target(@moonlog.fatal), @moonlog.Stream::Stderr)
}

///|
test "the level auto turns at is settable" {
  let console = @stdio.Console::new(
    stream=@moonlog.Stream::Auto,
    colour=false,
    from=@moonlog.warn,
  )
  assert_true(console.from() == @moonlog.warn)
  assert_eq(console.target(@moonlog.info), @moonlog.Stream::Stdout)
  assert_eq(console.target(@moonlog.warn), @moonlog.Stream::Stderr)
}

///|
test "a fixed stream keeps every level" {
  let errors = @stdio.Console::new(stream=@moonlog.Stream::Stderr, colour=false)
  assert_eq(errors.target(@moonlog.trace), @moonlog.Stream::Stderr)
  assert_eq(errors.target(@moonlog.fatal), @moonlog.Stream::Stderr)
  let out = @stdio.Console::new(stream=@moonlog.Stream::Stdout, colour=false)
  assert_eq(out.target(@moonlog.fatal), @moonlog.Stream::Stdout)
}

///|
test "the console defaults to auto, from error, and no colour when it is given none" {
  let console = @stdio.Console::new(colour=false)
  assert_eq(console.stream(), @moonlog.Stream::Auto)
  assert_true(console.from() == @moonlog.error)
  assert_false(console.coloured())
}

///|
test "a console slot is coloured the way the console decided" {
  let console = @stdio.Console::new(stream=@moonlog.Stream::Stdout, colour=true)
  assert_true(console.coloured())
  let hub = @moonlog.Hub::new()
  ignore(hub.add(console.slot(name="out")))
  let status = hub.status()
  assert_eq(status.length(), 1)
  assert_eq(status[0].name, "out")
  assert_eq(status[0].kind, "stdio")
}

///|
test "a line reaches the console it was addressed to" {
  let quiet = @stdio.Console::new(stream=@moonlog.Stream::Stdout, colour=false)
  let entry : @moonlog.Entry = {
    record: @moonlog.Record::of(@moonlog.info, "stdio", "a line from the test"),
    line: "a line from the test",
  }
  match quiet.write(entry) {
    Ok(_) => ()
    Err(why) => fail("the console refused the line: " + why)
  }
}
