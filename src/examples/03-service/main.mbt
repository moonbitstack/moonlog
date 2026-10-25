// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A service-shaped application: a console slot, a status slot that keeps only
/// warnings, a sampled slot for a chatty neighbour, and a remote slot that is
/// down with an alarm that falls back to the console.
///
///     moon run src/examples/03-service
struct Remote {
  lines : Array[String]
  failing : Array[Bool]
}

///|
pub impl @moonlog.Sink for Remote with fn write(self, entry) {
  if self.failing[0] {
    Err("connection refused")
  } else {
    self.lines.push(entry.line)
    Ok(())
  }
}

///|
fn main raise {
  let now = [1_700_000_000_000_000_000L]
  let console = @moonlog.Memory::new()
  let status = @moonlog.Memory::new()
  let sampled = @moonlog.Memory::new()
  let remote : Remote = { lines: [], failing: [true], }

  let hub = @moonlog.Hub::new(
    identity=@moonlog.Identity::of(app="gateway", env="prod", instance="g-3"),
    clock=fn() { now[0] },
  )

  let _ = hub.add(
    @moonlog.Slot::new(console, name="console").layout(
      @moonlog.Pattern::parse(
        "{time:%H:%M:%S%.3f} {level:<5} {target}: {msg}{fields}",
      ),
    ),
  )
  let _ = hub.add(
    @moonlog.Slot::new(status, name="status")
    .at(@moonlog.warn)
    .process(@moonlog.Redact::new().key("authorization")),
  )
  let _ = hub.add(
    @moonlog.Slot::new(sampled, name="sampled")
    .at(@moonlog.trace)
    .layout(@moonlog.Logfmt::new())
    .process(@moonlog.Sample::new(first=2, every=10, per=60_000_000_000L)),
  )

  // A remote sink that is down: its failures go to the console instead.
  let oncall = @moonlog.Tiers::from([["console"]])
  let _ = hub.add(
    @moonlog.Slot::new(remote, name="remote")
    .layout(@moonlog.Logfmt::new())
    .on_fail(@moonlog.OnFail::Alarm(oncall)),
  )

  // One request, logged the way a handler logs it: a logger with the request's
  // own field bound to it, so every line of the request carries it.
  let request = hub
    .logger("gateway::http")
    .bound("request", @moonlog.Value::of_str("r-1"))
  request.info("GET /mirror", fields=[
    ("path", @moonlog.Value::of_str("/mirror")),
    ("authorization", @moonlog.Value::of_str("Bearer t0ken")),
  ])
  now[0] = now[0] + 1_000_000_000L
  request.warn("slow upstream", fields=[
    ("took_ms", @moonlog.Value::of_int(1200)),
  ])

  // A chatty health probe, the same message every time: two of every ten are
  // kept, and the ones kept carry the number they were.
  for i in 0..<25 {
    hub
    .logger("gateway::health")
    .info("probe", fields=[("n", @moonlog.Value::of_int(i))])
  }

  println("— the console —")
  let lines = console.lines()
  let shown = if lines.length() > 6 { 6 } else { lines.length() }
  for i in 0..<shown {
    println("  " + lines[i])
  }
  if lines.length() > shown {
    println("  … " + (lines.length() - shown).to_string() + " more")
  }
  println("")
  println("— the status slot: warnings only, one field masked —")
  for line in status.lines() {
    println("  " + line)
  }
  println("")
  println(
    "— the sampled slot: " +
    sampled.lines().length().to_string() +
    " lines kept of 27 written —",
  )
  for line in sampled.lines() {
    println("  " + line)
  }
  println("")
  println("— where the slots stand —")
  for slot in hub.status() {
    println(
      "  " +
      slot.name +
      ": " +
      slot.health.name().to_owned() +
      ", dropped " +
      slot.dropped.to_string() +
      ", skipped " +
      slot.skipped.to_string(),
    )
  }
}
