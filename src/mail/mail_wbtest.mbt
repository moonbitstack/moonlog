// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An entry as a hub would hand one to a sink.
fn entry_of(
  level : @moonlog.Level,
  at : Int64,
  msg : String,
  fields : Array[(String, @moonlog.Value)],
) -> @moonlog.Entry {
  {
    record: @moonlog.Record::of(level, "gateway", msg).stamped(at).sets(fields),
    line: "2023-11-14 22:13:20.000 " + level.name() + " gateway: " + msg,
  }
}

///|
/// A sink with a fixed clock, mailing to one recipient.
fn mailer() -> Mail {
  Mail::new(
    host="localhost",
    from="moonlog@example.com",
    to=["oncall@example.com"],
    level=@moonlog.error,
    window=30_000_000_000L,
    at_most=2,
    clock=fn() { 1_700_000_000_000_000_000L },
  )
}

///|
test "only the levels the sink is for are mailed" {
  let sink = mailer()
  ignore(
    sink.write(
      entry_of(@moonlog.info, 1_700_000_000_000_000_000L, "chatty", []),
    ),
  )
  ignore(
    sink.write(entry_of(@moonlog.warn, 1_700_000_000_000_000_000L, "warm", [])),
  )
  assert_eq(sink.pending(), 0)
  ignore(
    sink.write(
      entry_of(@moonlog.error, 1_700_000_000_000_000_000L, "broken", []),
    ),
  )
  ignore(
    sink.write(entry_of(@moonlog.fatal, 1_700_000_000_000_000_000L, "gone", [])),
  )
  assert_eq(sink.pending(), 2)
}

///|
test "a batch is due when the window has passed or the mail is full" {
  let sink = mailer()
  let at = 1_700_000_000_000_000_000L
  assert_false(sink.due(at))
  ignore(sink.write(entry_of(@moonlog.error, at, "one", [])))
  assert_false(sink.due(at + 1_000_000_000L))
  assert_true(sink.due(at + 31_000_000_000L))
  ignore(sink.write(entry_of(@moonlog.error, at, "two", [])))
  assert_true(sink.due(at))
}

///|
test "the subject says how many records, how badly, and from where" {
  let sink = mailer()
  let at = 1_700_000_000_000_000_000L
  ignore(sink.write(entry_of(@moonlog.error, at, "one", [])))
  ignore(sink.write(entry_of(@moonlog.fatal, at, "two", [])))
  let batch = sink.take()
  assert_eq(sink.subject_for(batch), "FATAL: 2 records from gateway")
  // One record is a record, not a records.
  ignore(sink.write(entry_of(@moonlog.error, at, "three", [])))
  assert_eq(sink.subject_for(sink.take()), "ERROR: 1 record from gateway")
}

///|
test "the bodies carry every line, and the table escapes what HTML would eat" {
  let sink = mailer()
  let at = 1_700_000_000_000_000_000L
  ignore(
    sink.write(
      entry_of(@moonlog.error, at, "a <b> & a \"c\"", [
        ("took_ms", @moonlog.Value::of_int(12)),
      ]),
    ),
  )
  let batch = sink.take()
  let text = sink.text_for(batch)
  assert_true(text.contains("a <b> & a \"c\""))
  let html = sink.html_for(batch)
  assert_true(html.contains("a &lt;b&gt; &amp; a &quot;c&quot;"))
  assert_true(html.contains("took_ms=12"))
  assert_true(html.has_prefix("<table"))
}

///|
test "the letter round-trips: what is encoded is what is read back" {
  let sink = mailer()
  let at = 1_700_000_000_000_000_000L
  ignore(sink.write(entry_of(@moonlog.error, at, "the disk is full", [])))
  ignore(
    sink.write(entry_of(@moonlog.error, at + 1_000_000_000L, "still full", [])),
  )
  let batch = sink.take()
  let letter = sink.letter(batch)
  let bytes = letter.encode()
  let read = @moonmail.Message::parse(bytes) catch {
    error => fail("the letter would not parse: " + @debug.to_string(error))
  }
  assert_eq(read.subject(), Some("ERROR: 2 records from gateway"))
  assert_eq(read.from().length(), 1)
  assert_eq(read.from()[0].address, "moonlog@example.com")
  assert_eq(read.to().length(), 1)
  let recipient = match read.to()[0] {
    @moonmail.Address::Mailbox(box) => box.address
    _ => fail("the recipient is not a mailbox")
  }
  assert_eq(recipient, "oncall@example.com")
  let text = match read.text() {
    Some(text) => text
    None => fail("the letter has no text part")
  }
  assert_true(text.contains("the disk is full"))
  assert_true(text.contains("still full"))
  let html = match read.html() {
    Some(html) => html
    None => fail("the letter has no html part")
  }
  assert_true(html.contains("<table"))
}

///|
test "a full queue drops the oldest record and counts it" {
  let sink = Mail::new(
    host="localhost",
    from="moonlog@example.com",
    to=["oncall@example.com"],
    capacity=1,
    clock=fn() { 0L },
  )
  ignore(sink.write(entry_of(@moonlog.error, 0L, "one", [])))
  ignore(sink.write(entry_of(@moonlog.error, 0L, "two", [])))
  assert_eq(sink.pending(), 1)
  assert_eq(sink.dropped(), 1L)
  assert_true(sink.text_for(sink.take()).contains("two"))
}

///|
test "a slot around the sink mails at the same level the sink does" {
  let sink = mailer()
  let hub = @moonlog.Hub::new(clock=fn() { 1_700_000_000_000_000_000L })
  ignore(hub.add(sink.slot()))
  hub.logger("gateway").warn("not mailed")
  hub.logger("gateway").error("mailed")
  assert_eq(sink.pending(), 1)
  let status = hub.status()[0]
  assert_eq(status.kind, "mail")
}

///|
#cfg(target="native")
async test "a mail reaches a running Mailpit" {
  let address = match @env.get_env_var("MOONLOG_SMTP_HOST") {
    Some(address) => address
    None => return
  }
  let sink = Mail::new(
    host=address,
    port=1025,
    from="moonlog@example.com",
    to=["oncall@example.com"],
    at_most=2,
    clock=fn() { @env.now().reinterpret_as_int64() * 1_000_000L },
  )
  let at = @env.now().reinterpret_as_int64() * 1_000_000L
  ignore(sink.write(entry_of(@moonlog.error, at, "the disk is full", [])))
  ignore(sink.write(entry_of(@moonlog.error, at, "still full", [])))
  match sink.send() {
    Ok(count) => assert_eq(count, 2)
    Err(why) => fail("the mail was refused: " + why)
  }
  assert_eq(sink.pending(), 0)
  assert_eq(sink.sent(), 2L)
}
