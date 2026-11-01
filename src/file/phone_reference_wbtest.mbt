// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The same three lines, written to a file.
///
/// A file line is the line the console showed, byte for byte: the sink writes
/// the rendered entry and a newline, and nothing of its own. The expectation is
/// the reference example's console output (`rust/examples/phone.out` in the
/// reference repository), so a file this package writes and a console that
/// implementation writes hold the same bytes for the same records and layout.
#cfg(target="native")
test "a file holds the lines the reference implementation prints" {
  let dir = sandbox("reference")
  let path = dir + separator(dir) + "phone.log"
  let now = [1_700_000_000_000_000_000L]
  let file = File::new(path~, clock=fn() { now[0] })
  let hub = @moonlog.Hub::new(identity=@moonlog.Identity::of(app="mirror"), clock=fn() {
    now[0]
  })
  ignore(
    hub.add(
      @moonlog.Slot::new(file, name="console-1")
      .kind("console")
      .layout(@moonlog.Pattern::parse("{level:<5} {msg}{fields}")),
    ),
  )
  let log = hub.logger("sync").bound("mirror", @moonlog.Value::of_str("debian"))
  log.info("synced", fields=[("files", @moonlog.Value::of_int(42))])
  log.warn("disk nearly full", fields=[("free", @moonlog.Value::of_str("9%"))])
  log.error("sync failed", fields=[("tries", @moonlog.Value::of_int(3))])
  file.close()
  assert_eq(
    text_of(path),
    "INFO  synced mirror=debian files=42\n" +
    "WARN  disk nearly full mirror=debian free=9%\n" +
    "ERROR sync failed mirror=debian tries=3\n",
  )
  sand_out(dir)
}
