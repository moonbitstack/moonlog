// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sink of the kind an application writes for itself, which is what the
/// reference example is about: it texts a warning or worse to a phone.
struct ReferencePhone {
  lines : Array[String]
}

///|
impl @moonlog.Sink for ReferencePhone with fn write(self, entry) {
  self.lines.push(entry.line)
  Ok(())
}

///|
/// The example the reference implementation ships, read into a hub.
///
/// The document it loads is one console slot with `{level:<5} {msg}{fields}`
/// and one phone slot at `warn` with `{level} {msg}`; the records are the three
/// the example writes with `mirror = "debian"` bound. The expectation below is
/// the example's own recorded output (`rust/examples/phone.out`), which
/// `cargo run --example phone --features config` reproduces; nothing here is
/// tuned to make the comparison pass, and the config-refusal line the example
/// prints before any logging is not part of it.
test "the reference example's lines come out of this hub unchanged" {
  let console : Array[String] = []
  let phone : Array[String] = []
  let hub = @moonlog.Hub::new(identity=@moonlog.Identity::of(app="mirror"), clock=fn() {
    1_700_000_000_000_000_000L
  })
  ignore(
    hub.add(
      @moonlog.Slot::new(
        @moonlog.Lines::new(fn(line) { console.push(line) }),
        name="console-1",
      )
      .kind("console")
      .layout(@moonlog.Pattern::parse("{level:<5} {msg}{fields}")),
    ),
  )
  ignore(
    hub.add(
      @moonlog.Slot::new(ReferencePhone::{ lines: phone, }, name="oncall")
      .kind("phone")
      .filter(@moonlog.Filter::parse("warn"))
      .layout(@moonlog.Pattern::parse("{level} {msg}")),
    ),
  )
  let log = hub.logger("sync").bound("mirror", @moonlog.Value::of_str("debian"))
  log.info("synced", fields=[("files", @moonlog.Value::of_int(42))])
  log.warn("disk nearly full", fields=[("free", @moonlog.Value::of_str("9%"))])
  log.error("sync failed", fields=[("tries", @moonlog.Value::of_int(3))])

  assert_eq(console, [
    "INFO  synced mirror=debian files=42", "WARN  disk nearly full mirror=debian free=9%",
    "ERROR sync failed mirror=debian tries=3",
  ])
  assert_eq(phone, ["WARN disk nearly full", "ERROR sync failed"])
  let status : Array[String] = []
  for slot in hub.status() {
    status.push(
      slot.name + ": " + slot.kind + ", " + slot.health.name().to_owned(),
    )
  }
  assert_eq(status, ["console-1: console, up", "oncall: phone, up"])
}
