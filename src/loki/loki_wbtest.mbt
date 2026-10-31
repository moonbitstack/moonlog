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
    record: @moonlog.Record::of(level, "app", msg).stamped(at).sets(fields),
    line: msg,
  }
}

///|
test "a status is read as landed, refused or worth another try" {
  assert_eq(Verdict::of(204), Verdict::Accepted)
  assert_eq(Verdict::of(200), Verdict::Accepted)
  assert_eq(Verdict::of(400), Verdict::Refused)
  assert_eq(Verdict::of(404), Verdict::Refused)
  assert_eq(Verdict::of(429), Verdict::Retry)
  assert_eq(Verdict::of(500), Verdict::Retry)
  assert_eq(Verdict::of(503), Verdict::Retry)
  assert_eq(Verdict::of(408), Verdict::Retry)
}

///|
test "the push address is completed from the base address" {
  assert_eq(
    Loki::new(url="http://loki:3100").url(),
    "http://loki:3100/loki/api/v1/push",
  )
  assert_eq(
    Loki::new(url="http://loki:3100/").url(),
    "http://loki:3100/loki/api/v1/push",
  )
  assert_eq(
    Loki::new(url="https://loki.example.com/loki/api/v1/push").url(),
    "https://loki.example.com/loki/api/v1/push",
  )
}

///|
test "one stream per level, with the fields as structured metadata" {
  let sink = Loki::new(url="http://loki:3100", labels=[("job", "gateway")])
  ignore(
    sink.write(
      entry_of(@moonlog.info, 1_700_000_000_000_000_000L, "first", [
        ("trace", @moonlog.Value::of_str("abc")),
      ]),
    ),
  )
  ignore(
    sink.write(
      entry_of(@moonlog.error, 1_700_000_001_000_000_000L, "second", []),
    ),
  )
  ignore(
    sink.write(entry_of(@moonlog.info, 1_700_000_002_000_000_000L, "third", [])),
  )
  assert_eq(sink.pending(), 3)
  let body = sink.encode(sink.take())
  assert_eq(
    body,
    "{\"streams\":[" +
    "{\"stream\":{\"level\":\"info\",\"job\":\"gateway\"},\"values\":[" +
    "[\"1700000000000000000\",\"first\",{\"trace\":\"abc\"}]," +
    "[\"1700000002000000000\",\"third\"]]}," +
    "{\"stream\":{\"level\":\"error\",\"job\":\"gateway\"},\"values\":[" +
    "[\"1700000001000000000\",\"second\"]]}" +
    "]}",
  )
}

///|
test "a line is escaped as JSON, not pasted in" {
  let sink = Loki::new(url="http://loki:3100")
  ignore(sink.write(entry_of(@moonlog.warn, 0L, "a \"quoted\" \\ line", [])))
  let body = sink.encode(sink.take())
  assert_true(body.contains("a \\\"quoted\\\" \\\\ line"))
}

///|
test "a full queue drops the oldest entry and counts it" {
  let sink = Loki::new(
    url="http://loki:3100",
    limits=Limits::new(capacity=2, batch=2),
  )
  for word in ["one", "two", "three"] {
    ignore(sink.write(entry_of(@moonlog.info, 0L, word, [])))
  }
  assert_eq(sink.pending(), 2)
  assert_eq(sink.dropped(), 1L)
  let body = sink.encode(sink.take())
  assert_false(body.contains("one"))
  assert_true(body.contains("three"))
}

///|
test "a batch takes what it is allowed and leaves the rest in order" {
  let sink = Loki::new(
    url="http://loki:3100",
    limits=Limits::new(capacity=8, batch=2),
  )
  for word in ["one", "two", "three", "four"] {
    ignore(sink.write(entry_of(@moonlog.info, 0L, word, [])))
  }
  let first = sink.encode(sink.take())
  assert_true(first.contains("one"))
  assert_true(first.contains("two"))
  assert_false(first.contains("three"))
  assert_eq(sink.pending(), 2)
  // A batch that has to be tried again goes back in front of what arrived
  // since, so the history stays in order.
  sink.restore([{ level: @moonlog.info, at: 0L, line: "later", meta: [], }])
  let second = sink.encode(sink.take())
  assert_true(second.contains("later"))
  assert_true(
    second.has_prefix("{\"streams\":[{\"stream\":{\"level\":\"info\""),
  )
}

///|
#cfg(target="native")
async test "a push reaches a running Loki" {
  let address = match @env.get_env_var("MOONLOG_LOKI_URL") {
    Some(address) => address
    None => return
  }
  let sink = Loki::new(url=address, labels=[("job", "moonlog-test")])
  ignore(
    sink.write(entry_of(@moonlog.info, 0L, "moonlog pushes this line", [])),
  )
  let report = sink.push()
  assert_eq(report.sent, 1)
  assert_eq(report.rejected, 0)
  assert_eq(sink.sent(), 1L)
  assert_eq(sink.pending(), 0)
}
