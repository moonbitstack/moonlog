// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What the two network sinks would send, without a network: the push body a
/// Loki sink has queued and the mail an on-call inbox would get.
///
///     moon run --target native src/examples/07-shipping
fn main raise {
  let now = [1_700_000_000_000_000_000L]
  let loki = @loki.Loki::new(url="http://loki:3100", labels=[
    ("job", "gateway"),
    ("host", "g-1"),
  ])
  let mail = @mail.Mail::new(
    host="smtp.example.com",
    from="gateway@example.com",
    to=["oncall@example.com"],
    at_most=3,
    clock=fn() { now[0] },
  )
  let hub = @moonlog.Hub::new(clock=fn() { now[0] })
  ignore(hub.add(loki.slot()))
  ignore(hub.add(mail.slot()))
  let log = hub.logger("gateway")
  log.warn("the queue is backing up", fields=[
    ("depth", @moonlog.Value::of_int(4096)),
  ])
  now[0] = now[0] + 1_000_000_000L
  log.error("a writer was refused", fields=[
    ("writer", @moonlog.Value::of_str("shard-3")),
    ("retries", @moonlog.Value::of_int(2)),
  ])
  println(
    "loki holds " + loki.pending().to_string() + " entries and would push:",
  )
  println(loki.body())
  println("")
  println(
    "the mail holds " + mail.pending().to_string() + " and would go out as:",
  )
  let letter = mail.draft()
  match letter.subject() {
    Some(subject) => println("subject: " + subject)
    None => println("subject: none")
  }
  let encoded = letter.encode()
  let text = @utf8.decode_lossy(encoded)
  for line in text.split("\n") {
    if line.has_prefix("From:") ||
      line.has_prefix("To:") ||
      line.has_prefix("Subject:") ||
      line.has_prefix("Content-Type:") {
      println(line)
    }
  }
}
