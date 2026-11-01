// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The refusals the document shape of the shared specification makes, one path
/// at a time: a document that cannot be acted on has to say where it stopped,
/// because the operator holding it has nothing else to go on.
///
/// Each case is the smallest document that reaches the check, so a failure here
/// names the check rather than the document.

///|
/// Where a document was refused, or a failure saying it was not.
fn refusal_at(document : String) -> String raise {
  let answer : String? = try {
    ignore(Config::parse(document))
    None
  } catch {
    Refused(at~, ..) => Some(at)
  }
  match answer {
    Some(at) => at
    None => fail("the document was taken, and nothing refused it")
  }
}

///|
test "a sink without a kind is refused where the kind should be" {
  let document =
    #|sinks:
    #|  - { name: app, path: /var/log/app.log }
  assert_eq(refusal_at(document), "sinks.0.kind")
}

///|
test "a sink kind this package does not ship is refused where the kind is" {
  let document =
    #|sinks:
    #|  - kind: console
    #|  - { kind: phone, name: oncall, level: warn }
  assert_eq(refusal_at(document), "sinks.1.kind")
}

///|
test "an unknown step is refused where the step is" {
  let document =
    #|process: [{ fields: { region: cn } }, { rewrite: { a: b } }]
    #|sinks:
    #|  - kind: console
  assert_eq(refusal_at(document), "process.1")
}

///|
test "a level outside 0 to 255 is refused where it is defined" {
  let document =
    #|levels: { notice: { value: 300 } }
    #|sinks:
    #|  - kind: console
  assert_eq(refusal_at(document), "levels.notice")
}

///|
test "an alarm a sink points at has to be one the document defines" {
  let document =
    #|sinks:
    #|  - { kind: loki, url: "http://loki:3100", on_fail: ops }
    #|alarms:
    #|  pager: { tiers: [[stderr]] }
  assert_eq(refusal_at(document), "sinks.loki-1.on_fail")
}

///|
test "a document written in both spellings says so where the second one is" {
  let document =
    #|sinks:
    #|  - kind: console
    #|slots:
    #|  console: { kind: stdio }
  assert_eq(refusal_at(document), "slots")
}

///|
test "a slot may name a level the document defined, and gets its value" {
  let document =
    #|levels: { notice: { value: 35, colour: blue } }
    #|sinks:
    #|  - { kind: console, level: notice }
  let config = Config::parse(document)
  let slot = match config.slot("console-1") {
    Some(slot) => slot
    None => fail("no slot called console-1")
  }
  assert_eq(slot.filter, Some("35"))
}

///|
test "the document's level may name a level it defines, and the filter gets its value" {
  let document =
    #|levels: { notice: 35 }
    #|level: notice
    #|sinks:
    #|  - kind: console
  let config = Config::parse(document)
  assert_eq(config.filter(), "35")
}

///|
test "a level named where the reader has never heard of it is refused" {
  let document =
    #|level: shouty
  assert_eq(refusal_at(document), "level")
}

///|
test "a queue is written flat, the way a deployment file writes it" {
  let document =
    #|sinks:
    #|  - { kind: loki, url: "http://loki:3100", queue: 512, batch: 100, wait: 2s, full: block }
  let config = Config::parse(document)
  let slot = match config.slot("loki-1") {
    Some(slot) => slot
    None => fail("no slot called loki-1")
  }
  let queue = match slot.queue {
    Some(queue) => queue
    None => fail("the sink writes through a queue, not directly")
  }
  assert_eq(queue.size, 512)
  assert_eq(queue.batch, 100)
  assert_eq(queue.wait, 2_000_000_000L)
  assert_true(queue.full == @moonlog.Full::Block)
}

///|
test "`queue: 0` is a sink that writes directly" {
  let document =
    #|sinks:
    #|  - { kind: file, path: /var/log/app.log, queue: 0 }
  let config = Config::parse(document)
  let slot = match config.slot("file-1") {
    Some(slot) => slot
    None => fail("no slot called file-1")
  }
  assert_true(slot.queue is None)
}

///|
test "a queue of 0 leaves no room for a batch beside it" {
  let document =
    #|sinks:
    #|  - { kind: file, path: /var/log/app.log, queue: 0, batch: 100 }
  assert_eq(refusal_at(document), "sinks.0.batch")
}

///|
test "a sink takes `level` or `filter`, not both" {
  let document =
    #|sinks:
    #|  - { kind: console, level: warn, filter: info }
  assert_eq(refusal_at(document), "sinks.0.filter")
}

///|
test "a sink carries steps of its own, ahead of its layout" {
  let document =
    #|sinks:
    #|  - kind: console
    #|    process: [{ redact: [pass] }, { fields: { region: cn } }]
  let config = Config::parse(document)
  let slot = match config.slot("console-1") {
    Some(slot) => slot
    None => fail("no slot called console-1")
  }
  assert_eq(slot.chain.length(), 2)
}

///|
test "a filter names a level the document defined, wherever it sits" {
  let document =
    #|levels: { notice: 35 }
    #|filter: info, app=notice, notice/synced
    #|sinks:
    #|  - kind: console
  let config = Config::parse(document)
  assert_eq(config.filter(), "info,app=35,35/synced")
}

///|
test "a colour is the word the specification uses, or a flag" {
  let document =
    #|sinks:
    #|  - { kind: console, colour: always }
    #|  - { kind: console, colour: never }
    #|  - { kind: console, colour: true }
  let config = Config::parse(document)
  let first = match config.slot("console-1") {
    Some(slot) => slot
    None => fail("no slot called console-1")
  }
  assert_eq(first.colour, Some(true))
  let second = match config.slot("console-2") {
    Some(slot) => slot
    None => fail("no slot called console-2")
  }
  assert_eq(second.colour, Some(false))
}

///|
test "a file mode is written the way a mode is written" {
  let document =
    #|sinks:
    #|  - { kind: file, path: /var/log/app.log, perms: "0640" }
  let config = Config::parse(document)
  let slot = match config.slot("file-1") {
    Some(slot) => slot
    None => fail("no slot called file-1")
  }
  assert_eq(slot.count("perms"), Some(0o640))
}

///|
test "a name the document took is not handed to the next sink of its kind" {
  let document =
    #|sinks:
    #|  - { kind: file, name: file-1, path: /var/log/one.log }
    #|  - { kind: file, path: /var/log/two.log }
  let config = Config::parse(document)
  assert_eq(config.slots().length(), 2)
  assert_eq(config.slots()[0].name, "file-1")
  assert_eq(config.slots()[1].name, "file-2")
}

///|
test "a key this package cannot honour is refused where it sits" {
  let connect =
    #|sinks:
    #|  - { kind: loki, url: "http://loki:3100", connect: true }
  assert_eq(refusal_at(connect), "sinks.0.connect")
  let colours =
    #|sinks:
    #|  - { kind: console, colours: { warn: yellow } }
  assert_eq(refusal_at(colours), "sinks.0.colours")
  let reopen =
    #|sinks:
    #|  - { kind: file, path: /var/log/app.log, reopen: true }
  assert_eq(refusal_at(reopen), "sinks.0.reopen")
}

///|
/// A record to push through a step, with the instant the step sees.
fn kept_by(step : &@moonlog.Processor, at : Int64, msg : String) -> Bool {
  let record = @moonlog.Record::of(@moonlog.info, "app", msg).stamped(at)
  step.process(record, @moonlog.Env::at(at)) is Some(_)
}

///|
test "the steps keep the defaults the specification gives them" {
  let sample_document =
    #|process: [{ sample: {} }]
    #|sinks:
    #|  - kind: console
  let sample = Config::parse(sample_document)
  let step = sample.chain()[0]
  let mut kept = 0
  for _ in 0..<200 {
    if kept_by(step, 0L, "the same message") {
      kept = kept + 1
    }
  }
  // A hundred of a burst, then one in a hundred: the two hundredth is kept.
  assert_eq(kept, 101)
  let limit_document =
    #|process: [{ limit: { rate: 5 } }]
    #|sinks:
    #|  - kind: console
  let limit = Config::parse(limit_document)
  let bucket = limit.chain()[0]
  let mut through = 0
  for _ in 0..<10 {
    if kept_by(bucket, 0L, "the same message") {
      through = through + 1
    }
  }
  // The bucket holds a second's worth, so five go through and five wait.
  assert_eq(through, 5)
  let dedupe_document =
    #|process: [{ dedupe: {} }]
    #|sinks:
    #|  - kind: console
  let dedupe = Config::parse(dedupe_document)
  let repeats = dedupe.chain()[0]
  assert_true(kept_by(repeats, 0L, "same"))
  assert_false(kept_by(repeats, 500_000_000L, "same"))
  assert_true(kept_by(repeats, 1_500_000_000L, "same"))
}

///|
test "a slot's own steps survive a round trip through another format" {
  let document =
    #|sinks:
    #|  - kind: console
    #|    process: [{ redact: [pass] }, { fields: { region: cn } }]
  let config = Config::parse(document)
  let again = Config::parse(
    config.dump(format=Format::Json),
    format=Format::Json,
  )
  let slot = match again.slot("console-1") {
    Some(slot) => slot
    None => fail("no slot called console-1 after the round trip")
  }
  assert_eq(slot.chain.length(), 2)
  assert_eq(slot.process.length(), 2)
}
