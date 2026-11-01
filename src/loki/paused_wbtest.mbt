// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A push that meets a frozen server, which is why this file's test runs on its
/// own: the job pauses the container before it starts, and the test writes a
/// file when it is waiting, so the job knows when the pause has done its work
/// and the server may answer again. Every other test in the package expects a
/// server that is up.
///
/// What it proves: a push that finds the server away is worth another try, the
/// batch stays queued and in order, and the loop that owns the sink lands the
/// line once the server answers — where Loki's own API then reads it back,
/// which is the only proof the octets arrived as they were written.
#cfg(target="native")
async test "a push to a paused Loki waits, lands when it answers, and reads back" {
  let address = match @env.get_env_var("MOONLOG_LOKI_URL") {
    Some(address) => address
    None => return
  }
  let marker = match @env.get_env_var("MOONLOG_LOKI_WAITING") {
    Some(path) => path
    None => return
  }
  let sink = Loki::new(
    url=address,
    labels=[("job", "moonlog-test")],
    limits=Limits::new(batch=16, timeout=5),
  )
  ignore(sink.write(entry_of(@moonlog.warn, 0L, "moonlog waited for loki", [])))
  let first = sink.push()
  assert_true(first.retry is Some(_))
  assert_eq(first.sent, 0)
  assert_eq(sink.pending(), 1)
  assert_eq(sink.failures(), 1L)
  @fs.write_file(marker, "waiting")
  // The loop the application runs, which is the only retry this sink has.
  let mut tries = 0
  while tries < 120 && sink.pending() > 0 {
    @async.sleep(1_000)
    ignore(sink.push())
    tries = tries + 1
  }
  assert_eq(sink.pending(), 0)
  assert_eq(sink.sent(), 1L)
  let answer = @moonfetch.get(
    address + "/loki/api/v1/query_range",
    query=[("query", "{job=\"moonlog-test\"}"), ("limit", "50")],
    timeout=10,
  )
  assert_eq(answer.status, 200)
  let body = @utf8.decode_lossy(answer.body)
  assert_true(body.contains("moonlog waited for loki"))
}
