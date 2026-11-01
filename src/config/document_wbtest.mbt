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
