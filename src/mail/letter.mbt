// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How the connection to the mail server is protected.
pub(all) enum Security {
  Clear
  StartTls
  Tls
} derive(Eq, Debug)

///|
pub extend Security with Eq::{equal, not_equal}

///|
pub extend Security with Debug::{to_repr}

///|
/// The port a security setting usually means: 25 for the clear, 587 for
/// submission with STARTTLS, 465 for implicit TLS. The submission ports are
/// what a relay in front of a service listens on when it is not the local one.
pub fn Security::port(self : Security) -> Int32 {
  match self {
    Clear => 25
    StartTls => 587
    Tls => 465
  }
}

///|
/// How long a batch of records is gathered before it is mailed.
pub let window_default : Int64 = 60_000_000_000L

///|
/// How many records one mail carries; a burst larger than this is sent in
/// several mails rather than one too big to read.
pub let at_most_default : Int32 = 100

///|
/// One record waiting to be mailed.
struct Held {
  at : Int64
  level : @moonlog.Level
  target : String
  line : String
  fields : Array[(String, @moonlog.Value)]
}
