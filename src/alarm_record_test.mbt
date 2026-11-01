// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The record an incident becomes, as the shared specification describes it and
/// as the implementations that came before this one write it: the level, the
/// target, the message per phase, and the fields every implementation puts on
/// it — including `since`, which is a timestamp rather than a count of
/// nanoseconds.
///
/// | phase | level | message |
/// |:--|:--:|:--|
/// | `opened` | error | ``sink `name` failed: …`` |
/// | `reminder` | error | ``sink `name` is still failing: …`` |
/// | `resolved` | info | ``sink `name` works again after Ns`` |

///|
/// One field of a record as text, which is how these read in every layout.
fn incident_field(record : @moonlog.Record, key : String) -> String {
  match record.field(key) {
    Some(value) => value.to_text()
    None => "?"
  }
}

///|
test "an incident becomes the record the other implementations write" {
  let incident = @moonlog.Incident::new(
    "loki",
    "loki",
    @moonlog.Phase::Opened,
    "connection refused",
    1_700_000_000_000_000_000L,
  )
  let opened = incident.describe()
  assert_true(opened.level == @moonlog.error)
  assert_eq(opened.target, "serlog")
  assert_eq(opened.msg, "sink `loki` failed: connection refused")
  assert_eq(incident_field(opened, "sink"), "loki")
  assert_eq(incident_field(opened, "kind"), "loki")
  assert_eq(incident_field(opened, "phase"), "opened")
  assert_eq(incident_field(opened, "skipped"), "0")
  assert_eq(incident_field(opened, "dropped"), "0")
  assert_eq(incident_field(opened, "since"), "2023-11-14T22:13:20.000000000Z")
  let reminder = @moonlog.Incident::new(
    "loki",
    "loki",
    @moonlog.Phase::Reminder,
    "connection refused",
    1_700_000_000_000_000_000L,
  )
  assert_eq(
    reminder.describe().msg,
    "sink `loki` is still failing: connection refused",
  )
  let resolved = @moonlog.Incident::new(
    "loki",
    "loki",
    @moonlog.Phase::Resolved,
    "",
    1_700_000_000_000_000_000L,
  )
  resolved.at = 1_700_000_065_000_000_000L
  let again = resolved.describe()
  assert_true(again.level == @moonlog.info)
  assert_eq(again.msg, "sink `loki` works again after 65s")
  // Two failures of one incident read as one field, separated the way every
  // implementation separates them.
  let walked = @moonlog.Incident::new(
    "app",
    "file",
    @moonlog.Phase::Opened,
    "the disk is full",
    0L,
  )
  walked.failures.push({ sink: "loki", error: "connection refused", at: 0L, })
  assert_eq(
    incident_field(walked.describe(), "failures"),
    "app: the disk is full; loki: connection refused",
  )
}
