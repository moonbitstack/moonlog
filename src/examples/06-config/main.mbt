// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A document read, checked, read back and written out again in another
/// format: what a deployment file goes through before a process starts.
///
///     moon run src/examples/06-config
fn main raise {
  let document =
    #|profile: tracing
    #|filter: info, gateway=debug, noisy=off
    #|alarm:
    #|  tiers:
    #|    - [loki]
    #|    - [console]
    #|  remind: 10m
    #|slots:
    #|  console:
    #|    kind: stdio
    #|    stream: auto
    #|    layout: "{time:%H:%M:%S} {level:<5} {target}: {msg}"
    #|  app:
    #|    kind: file
    #|    path: /var/log/gateway/app.log
    #|    max_size: 64mb
    #|    every: 24h
    #|    keep: 7
    #|    compress: true
    #|    queue:
    #|      size: 8192
    #|      wait: 2s
    #|  loki:
    #|    kind: loki
    #|    url: http://loki:3100
    #|    labels:
    #|      job: gateway
  let config = @config.Config::parse(document)
  println("profile " + config.profile().name().to_owned())
  println("filter " + config.filter())
  for slot in config.slots() {
    println("slot " + slot.name + " is a " + slot.kind)
    for key in slot.keys() {
      match slot.text(key) {
        Some(text) => println("  " + key + " = " + text)
        None =>
          match slot.size(key) {
            Some(size) =>
              println("  " + key + " = " + size.to_string() + " bytes")
            None =>
              match slot.span(key) {
                Some(span) =>
                  println("  " + key + " = " + @config.nanos_as_span(span))
                None => ()
              }
          }
      }
    }
    match slot.queue {
      Some(queue) =>
        println(
          "  queue holds " +
          queue.size.to_string() +
          " and writes " +
          queue.batch.to_string() +
          " at a time",
        )
      None => ()
    }
  }
  match config.alarm() {
    Some(alarm) =>
      println(
        "alarm walks " +
        alarm.tiers.length().to_string() +
        " tiers, reminding every " +
        @config.nanos_as_span(alarm.remind),
      )
    None => ()
  }
  println("the same configuration in TOML:")
  println(config.dump(format=@config.Format::Toml))
  let again = @config.Config::parse(
    config.dump(format=@config.Format::Toml),
    format=@config.Format::Toml,
  )
  println(
    "written and read back: " +
    again.slots().length().to_string() +
    " slots, filter " +
    again.filter(),
  )
}
