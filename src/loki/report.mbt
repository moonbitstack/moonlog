// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What one push did.
///
/// A batch either lands, is refused for good, or is worth trying again: Loki
/// answers 400 for an entry it will never take — a timestamp outside the
/// tenant's window is the usual one — and 429 or 5xx when it is merely busy.
/// Sending the first kind again would spin for ever, so those entries are
/// dropped and counted, and only the second kind comes back to the queue.
pub(all) struct Report {
  sent : Int32
  rejected : Int32
  retry : String?
}

///|
/// Nothing was pending, so nothing was tried.
pub fn Report::idle() -> Report {
  { sent: 0, rejected: 0, retry: None, }
}

///|
/// Whether the push asked to be repeated.
pub fn Report::pushed(self : Report) -> Bool {
  self.retry is None
}

///|
/// What to do with a batch that came back as `status`.
pub(all) enum Verdict {
  Accepted
  Refused
  Retry
} derive(Eq, Debug)

///|
pub extend Verdict with Eq::{equal, not_equal}

///|
pub extend Verdict with Debug::{to_repr}

///|
/// How a status is read: 2xx landed, 400 and 404 will never land, everything
/// else — 408, 429, 5xx — is worth another try.
pub fn Verdict::of(status : Int32) -> Verdict {
  match status {
    200..<300 => Accepted
    400..<500 => if status == 408 || status == 429 { Retry } else { Refused }
    _ => Retry
  }
}

///|
/// The reason a status gives for trying again.
fn reason_of(status : Int32) -> String {
  if status == 429 {
    "loki is pushing back: too many requests"
  } else if status >= 500 {
    "loki answered " + status.to_string()
  } else if status == 408 {
    "loki timed out"
  } else {
    "loki answered " + status.to_string()
  }
}
