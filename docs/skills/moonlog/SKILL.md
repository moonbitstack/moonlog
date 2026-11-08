---
name: moonlog
description: "Structured logging for MoonBit: six levels, typed fields, filters by target and level, processor chains, four layouts with ten JSON schemas, sinks behind a health machine, alarms across tiers, a rotating file, Loki and mail sinks, a deployment document and a process-wide hub. Use when a MoonBit program has to log, ship its lines to a collector, write in another logger's format, or read a logging configuration file."
---

# moonlog

A logger produces a record; a hub filters and reshapes it; a slot lays it out and
hands it to a sink. Time is a parameter and nothing is global, so a test names
the instant a line carries and the same code replays without waiting.

```bash
moon add moonbitstack/moonlog
```

```
import {
  "moonbitstack/moonlog" @log,
}
```

`@log` is an import alias, not a second package: `@moonlog` and `@serlog` name
the same items, and the examples in the repository use all three. The root
package only formats; `moonlog/stdio`, `moonlog/file`, `moonlog/loki`,
`moonlog/mail`, `moonlog/config` and `moonlog/global` are where a line reaches a
console, a disk or a socket.

## Write lines

A hub owns the clock, the filter and the slots. A logger carries a target and
the fields bound to it. `Lines` is the sink that proves the seam: it hands each
rendered line to a function.

```moonbit
let lines : Array[String] = []
let sink = @log.Lines::new(fn(line) { lines.push(line) })
let hub = @log.Hub::new(clock=fn() { 1_700_000_000_000_000_000L })
let _ = hub.add(@log.Slot::new(sink, name="audit"))
let log = hub.logger("sync::pull")
log.info("started", fields=[("shards", @log.Value::of_int(4))])
assert_eq(lines[0], "2023-11-14 22:13:20.000 INFO  sync::pull: started shards=4")
```

`Memory` keeps the newest entries for a test to read, and `Discard` throws them
away. `Value` is typed — `of_int`, `of_float`, `of_str`, `of_bool`, `of_long`,
`of_list`, `of_map`, `of_error` — because the layout, not the call site,
decides how a field reads in text and in JSON.

## Narrow what reaches a slot

The hub filters once for everyone; a slot then adds its own level floor, filter
and steps. A spec is comma-separated: a bare level is the default for targets no
directive names, `target=level` covers that target and everything under it, and
`off` silences one.

```moonbit
let noisy = @log.Filter::parse("info, sync=debug, sync::poll=off")
assert_eq(noisy.allows(@log.debug, "sync::pull"), true)
assert_eq(noisy.allows(@log.error, "sync::poll"), false)
let _ = hub.add(
  @log.Slot::new(sink, name="errors")
  .at(@log.error)
  .filter(noisy)
  .process(@log.Redact::new().key("token"))
  .process(@log.Sanitise::new()),
)
```

The eight steps are `Redact`, `Sanitise`, `Fields`, `Keep`, `Exclude`, `Sample`,
`Limit` and `Dedupe`. A step of your own implements `@log.Processor`:
`process(record, env) -> Record?`, where `None` drops the record. Chain a
`Sample` and a `Limit` on a chatty target rather than raising the level.

## Reach a console, a file, or a document

The console and the file are sinks with slots of their own. A file opens on its
first line, so a path it cannot open becomes a failing slot instead of a panic at
startup.

```moonbit native
let document =
  #|sinks:
  #|  - { kind: console, name: console }
  #|  - { kind: file, name: app, path: /var/log/app.log, max_size: 64mb, keep: 7 }
let config = @config.Config::parse(document)
assert_eq(config.slots().length(), 2)
@global.start(config=config)
@global.logger("gateway").info("serving", fields=[("port", @log.Value::of_int(8080))])
@global.flush()
```

`@global` is the one process-wide hub, and an application is the only thing that
imports it: a library takes a `Logger` as a parameter and writes through it.
Without a document, `start` builds a console from the profile and reads
`SERLOG_COMPAT`, `SERLOG_FILTER` and `SERLOG_FORMAT`, so a program that says
nothing still logs.

## Rules that catch people out

- Nothing in the root package reads a clock. The hub asks the `clock` it was
  given; the identity's `offset` decides local time. In a test, pass both and the
  output is fixed.
- A message is a `String`, built at the call site. There is no format language
  and no missing-argument failure.
- Ask `hub.enabled(level)` or `log.enabled(level)` before building fields that
  cost something.
- `File`, `Loki`, `Mail` and `global` write through the native backend; the
  console, the layouts, the filters and `Config::parse` compile on all four
  targets. Mark such code `native` in a `.mbt` file, not optional at run time.
- Loki and mail queue instead of writing: call `loki.push()` and `mail.send()`
  from an async loop you already run, or `@global.drain()`. A batch worth
  retrying comes back at the front of the queue; a batch the server refuses for
  good is dropped and counted.
- A failing write moves the slot's breaker to `down`, which skips records and
  counts them until the next probe. Tell a slot what to do about it with
  `on_fail`: `Ignore`, `Panic`, or `Alarm(Tiers::from([["loki"], ["mail"]]))`.
- A document may name a sink of your own: pass a `@config.Kind` to
  `Config::parse` with the keys it reads, and build it from the slot.
