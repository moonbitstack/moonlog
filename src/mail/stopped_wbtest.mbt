// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A mail server that is stopped and started again, which is why this file's
/// test runs on its own: the job stops Mailpit before it starts, and the test
/// writes a file when it is waiting, so the job knows when the stopped server
/// has done its work and the mail may go out. Every other test in the package
/// expects a server that is up.
///
/// What it proves: the failure of a send is an answer the caller's loop acts
/// on, the records stay queued in order, the slot's health machine goes down
/// and up again, and the letter that waited is in Mailpit's own API once the
/// retry lands — one mail, both records, the words they were written with.
#cfg(target="native")
async test "a stopped Mailpit is retried, and the letter arrives when it is back" {
  let host = match @env.get_env_var("MOONLOG_SMTP_HOST") {
    Some(host) => host
    None => return
  }
  let marker = match @env.get_env_var("MOONLOG_SMTP_WAITING") {
    Some(path) => path
    None => return
  }
  let api = match @env.get_env_var("MOONLOG_MAILPIT_URL") {
    Some(url) => url
    None => "http://127.0.0.1:8025"
  }
  let nanos = fn() { @env.now().reinterpret_as_int64() * 1_000_000L }
  let sink = Mail::new(
    host~,
    port=1025,
    from="moonlog@example.com",
    to=["oncall@example.com"],
    at_most=2,
    clock=nanos,
  )
  // The machine a mail slot runs, driven by the same failures the slot would
  // see: nothing else in this library reports a refused send.
  let breaker = @moonlog.Breaker::new(5_000_000_000L, 0L)
  ignore(sink.write(entry_of(@moonlog.error, 0L, "the disk is full", [])))
  ignore(sink.write(entry_of(@moonlog.error, 0L, "still full", [])))
  match sink.send() {
    Ok(count) => fail("a stopped server took " + count.to_string() + " records")
    Err(_) => ()
  }
  assert_eq(sink.pending(), 2)
  assert_eq(sink.failures(), 1L)
  assert_eq(sink.sent(), 0L)
  assert_eq(
    breaker.fault(
      0L,
      "mailpit is stopped",
      3_600_000_000_000L,
      @moonlog.Tell::Report,
    ),
    Some(@moonlog.Phase::Opened),
  )
  assert_eq(breaker.health(), @moonlog.Health::Down)
  @fs.write_file(marker, "waiting")
  // The loop an application runs: wait, try the same batch again.
  let mut tries = 0
  let mut delivered = 0
  while tries < 120 && sink.pending() > 0 {
    @async.sleep(1_000)
    match sink.send() {
      Ok(count) => delivered = count
      Err(_) => ()
    }
    tries = tries + 1
  }
  assert_eq(delivered, 2)
  assert_eq(sink.pending(), 0)
  assert_eq(sink.sent(), 2L)
  let at = nanos()
  assert_true(breaker.admit(at))
  assert_eq(breaker.pass(at), Some(@moonlog.Phase::Resolved))
  assert_eq(breaker.health(), @moonlog.Health::Up)
  // Mailpit's API is the only proof the octets arrived: one mail carrying both
  // records, in the words they were written with.
  let listing = @moonfetch.get(api + "/api/v1/messages", timeout=10)
  assert_eq(listing.status, 200)
  let list = @utf8.decode_lossy(listing.body)
  let id = match list.find("\"ID\":\"") {
    Some(at) => {
      let rest = list[at + 6:]
      match rest.find("\"") {
        Some(end) => rest[:end].to_owned()
        None => ""
      }
    }
    None => ""
  }
  assert_true(id != "")
  let detail = @moonfetch.get(api + "/api/v1/message/" + id, timeout=10)
  assert_eq(detail.status, 200)
  let letter = @utf8.decode_lossy(detail.body)
  assert_true(letter.contains("2 records from gateway"))
  assert_true(letter.contains("the disk is full"))
  assert_true(letter.contains("still full"))
}
