///|
fn run(
  step : &@moonlog.Processor,
  record : @moonlog.Record,
  now? : Int64,
) -> @moonlog.Record? {
  step.process(record, @moonlog.Env::at(now.unwrap_or(0L)))
}

///|
fn text_of(record : @moonlog.Record, key : String) -> String {
  match record.field(key) {
    Some(value) => value.to_text()
    None => "<absent>"
  }
}

///|
test "redact masks a key at any depth, a dotted path, and message patterns" {
  let record = @moonlog.Record::of(@moonlog.info, "app", "token=abc123 ok")
    .set("password", @moonlog.Value::of_str("hunter2"))
    .set(
      "req",
      @moonlog.Value::of_map([
        (
          "headers",
          @moonlog.Value::of_map([
            ("authorization", @moonlog.Value::of_str("Bearer x")),
          ]),
        ),
        ("password", @moonlog.Value::of_str("inner")),
      ]),
    )
    .set("user", @moonlog.Value::of_str("leo"))
  let step = @moonlog.Redact::new()
    .key("password")
    .path("req.headers.authorization")
    .pattern("token=[a-z0-9]+")
    .mask("[hidden]")
  let out = run(step, record).unwrap()
  assert_eq(out.msg, "[hidden] ok")
  assert_eq(text_of(out, "password"), "[hidden]")
  assert_eq(
    text_of(out, "req"),
    "{headers={authorization=[hidden]}, password=[hidden]}",
  )
  assert_eq(text_of(out, "user"), "leo")
  assert_eq(text_of(record, "password"), "hunter2")
}

///|
test "redact leaves a record that has nothing to mask as it was" {
  let record = @moonlog.Record::of(@moonlog.info, "app", "plain").set(
    "user",
    @moonlog.Value::of_str("leo"),
  )
  let out = run(
    @moonlog.Redact::new().key("password").pattern("secret"),
    record,
  ).unwrap()
  assert_eq(out.msg, "plain")
  assert_eq(text_of(out, "user"), "leo")
}

///|
test "redact replaces empty matches without losing the text around them" {
  let record = @moonlog.Record::of(@moonlog.info, "app", "abc")
  let out = run(@moonlog.Redact::new().pattern("x*").mask("-"), record).unwrap()
  assert_eq(out.msg, "-a-b-c-")
  let mixed = run(
    @moonlog.Redact::new().pattern("x*").mask("-"),
    record.say("xab"),
  ).unwrap()
  assert_eq(mixed.msg, "--a-b-")
}

///|
test "redact refuses a pattern that is not a regular expression" {
  let refused = try {
    ignore(@moonlog.Redact::new().pattern("(unclosed"))
    false
  } catch {
    @moonlog.Refused(got~, ..) => got == "(unclosed"
  }
  assert_eq(refused, true)
}

///|
test "sanitise escapes control characters in the message and in string fields" {
  let record = @moonlog.Record::of(
      @moonlog.info, "app", "a\nb\rc\td\u{1}e\u{7f}",
    )
    .set("note", @moonlog.Value::of_str("x\ny"))
    .set("count", @moonlog.Value::of_int(3))
  let out = run(@moonlog.Sanitise::new(), record).unwrap()
  assert_eq(out.msg, "a\\nb\\rc\\td\\u{0001}e\\u{007f}")
  let escape = run(@moonlog.Sanitise::new(), record.say("\u{1b}[31m")).unwrap()
  assert_eq(escape.msg, "\\u{001b}[31m")
  assert_eq(text_of(out, "note"), "x\\ny")
  assert_eq(text_of(out, "count"), "3")
  let clean = @moonlog.Record::of(@moonlog.info, "app", "fine")
  assert_eq(run(@moonlog.Sanitise::new(), clean).unwrap().msg, "fine")
}

///|
test "keep and exclude decide by level, tag and field" {
  let record = @moonlog.Record::of(@moonlog.warn, "app", "m")
    .tag("audit")
    .set("region", @moonlog.Value::of_str("eu"))
  let keep = @moonlog.Keep::new()
    .level(@moonlog.info)
    .tag("audit")
    .field("region", "eu")
  assert_eq(run(keep, record) is Some(_), true)
  assert_eq(
    run(@moonlog.Keep::new().level(@moonlog.error), record) is None,
    true,
  )
  assert_eq(run(@moonlog.Keep::new().tag("billing"), record) is None, true)
  assert_eq(
    run(@moonlog.Keep::new().field("region", "us"), record) is None,
    true,
  )
  assert_eq(
    run(@moonlog.Keep::new().field("missing", "x"), record) is None,
    true,
  )
  assert_eq(run(@moonlog.Keep::new(), record) is Some(_), true)
  let exclude = @moonlog.Exclude::new()
    .tag("audit")
    .field("region", "eu")
    .level(@moonlog.warn)
  assert_eq(run(exclude, record) is None, true)
  assert_eq(
    run(@moonlog.Exclude::new().tag("billing"), record) is Some(_),
    true,
  )
  assert_eq(run(@moonlog.Exclude::new(), record) is None, true)
}

///|
test "fields adds to every record and replaces a field of the same name" {
  let step = @moonlog.Fields::new()
    .set("service", @moonlog.Value::of_str("api"))
    .set("region", @moonlog.Value::of_str("eu"))
  let record = @moonlog.Record::of(@moonlog.info, "app", "m").set(
    "region",
    @moonlog.Value::of_str("us"),
  )
  let out = run(step, record).unwrap()
  assert_eq(text_of(out, "service"), "api")
  assert_eq(text_of(out, "region"), "eu")
}

///|
test "limit lets a burst through, then the rate" {
  let step = @moonlog.Limit::new(rate=1.0, burst=2.0)
  let record = @moonlog.Record::of(@moonlog.info, "app", "m")
  let kept = [0L, 0L, 0L, 500_000_000L, 1_000_000_000L, 2_000_000_000L].map(t => {
    run(step, record, now=t) is Some(_)
  })
  assert_eq(kept, [true, true, false, false, true, true])
  let tiny = @moonlog.Limit::new(rate=1.0, burst=0.0)
  assert_eq(run(tiny, record, now=0L) is Some(_), true)
}

///|
test "dedupe drops a repeat within the window and counts it on the next kept" {
  let step = @moonlog.Dedupe::new(within=1_000_000_000L)
  let record = @moonlog.Record::of(@moonlog.info, "app", "same")
  assert_eq(run(step, record, now=0L) is Some(_), true)
  assert_eq(run(step, record, now=100L) is None, true)
  assert_eq(run(step, record, now=200L) is None, true)
  let next = run(step, record, now=2_000_000_000L).unwrap()
  assert_eq(text_of(next, "repeated"), "2")
}
