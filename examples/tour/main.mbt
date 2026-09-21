// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The whole surface in one run.
fn main {
  // The seam: a logger writes through a function, so where the lines go is the
  // caller's to decide. Here they go to stdout.
  let log = @moonlog.Logger::new(@moonlog.Lines::new(line => println(line)))
  log.info("listening", fields=[("port", Json::number(8000))])
  log.warn("slow response", fields=[
    ("path", Json::string("/report")),
    ("ms", Json::number(1840)),
  ])
  log.error("upstream refused the connection")

  // Below the level, nothing is written, and `enabled` says so first — the point
  // being that an expensive message never gets assembled.
  log.debug("this does not appear")
  println("debug enabled: \{log.enabled(Debug)}")
  println("info enabled:  \{log.enabled(Info)}")

  // A logger at another level, from the same seam.
  let chatty = log.at(Trace)
  chatty.debug("now it appears", fields=[("why", Json::string("level=Trace"))])

  // One JSON object per line, for something that is read by a machine.
  let structured = @moonlog.Logger::new(
    @moonlog.Lines::new(line => println(line), format=@moonlog.json_line),
  )
  structured.info("listening", fields=[
    ("port", Json::number(8000)),
    ("tls", Json::boolean(false)),
  ])

  // A sink of one's own: anything that can take a record.
  let held : Array[String] = []
  let capture = @moonlog.Logger::new(
    @moonlog.Lines::new(line => held.push(line)),
    level=Trace,
  )
  capture.trace("kept, not printed")
  capture.fatal("the last thing said")
  println("captured \{held.length()}: \{held[0]} | \{held[1]}")

  // Silence is not a level: it answers false at every one.
  let quiet = @moonlog.Logger::silent()
  quiet.error("nobody hears this")
  println("silent enabled at Fatal: \{quiet.enabled(Fatal)}")
  println("silent level: \{quiet.level() is None}")

  // A level by name, for a configuration file — and `None` for one with a typo
  // in it, rather than a verbosity nobody asked for.
  for name in ["trace", "WARN", "Critical", "chatty"] {
    let got = @moonlog.Level::parse(name[:])
    println(
      "\{name} -> \{match got { Some(l) => l.name(); None => "not a level" }}",
    )
  }
}
