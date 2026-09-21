# moonlog

Structured logging for MoonBit: a level, a message, fields carried as values,
and a seam to write through. It writes nowhere by itself.

```moonbit
let log = @moonlog.Logger::new(@moonlog.Lines::new(line => println(line)))

log.info("listening", fields=[("port", Json::number(8000))])
log.warn("slow response", fields=[("path", Json::string("/report"))])
// INFO listening port=8000
// WARNING slow response path="/report"

// One JSON object per line, for a reader that is a machine.
@moonlog.Lines::new(line => println(line), format=@moonlog.json_line)
// {"level":"INFO","msg":"listening","port":8000}
```

Run `moon run examples/tour` for the whole surface in one go.

## What it does not do

**No clock.** A record has no timestamp. Reading a clock is a side effect, and a
logger that stamps the time cannot be tested for what it wrote; a sink that wants
timestamps is handed a clock when it is built. The same reasoning as `mooncred`
taking the instant it verifies against.

**No global logger.** There is no process-wide state to configure and no
implicit default to inherit. A logger is a value: it is passed in, and a library
that was handed none logs nothing.

**No output of its own.** `Lines::new(write)` calls `write` and that is all. It
prints when the function prints, fills an array when the function fills an array,
and reaches an embedder's own logging when the function does that.

**No formatting.** A message is a `String`, built at the call site with string
interpolation. A library that formats needs a format language, an escape for it,
and a way to be wrong about the argument count.

## Levels

Six, ordered from most verbose to least: `Trace`, `Debug`, `Info`, `Warning`,
`Error`, `Fatal`. A message is written when its level is at least the logger's.

They are the union of what the libraries here already had, named as they named
them, so migrating is not also a rename. `Critical` and `Fatal` are one level
under two names and `Fatal` is the one kept; `Panic`, which etcd's logger also
aborts on, is not a level but something the caller does after logging at `Fatal`.
`Level::parse` accepts the other spellings — `warn`, `err`, `critical` — so a
configuration written for another library keeps working, and answers `None` for a
name it does not know rather than falling back to a verbosity nobody asked for.

**Silence is not a level.** `Logger::silent()` answers `false` from `enabled` at
every level, so a caller that only builds an expensive message when it will be
used builds none at all. A logger at `Fatal` would still say yes to `Fatal`.

## Configuration

| Setting | Default | Why that one |
|:--:|:--:|:--|
| `level` | `Info` | What every library here defaulted to, and what Python's `logging`, Go's `slog` and go-zero settle on |
| `format` on `Lines` | `line` | `LEVEL message key=value`, which is what a person reads. `json_line` is the one a machine reads |
| `level_key` / `message_key` | `level` / `msg` | What go-zero, zap and `slog` name them, so a line drops into a pipeline built for one of those. `object(record, level~, message~)` renames them for a pipeline that wants `severity` |

Fields are `(String, Json)`. `Json` is a builtin, so carrying values rather than
pre-formatted text costs no dependency and lets the sink decide how they read —
the text sink writes each as its JSON, so a field with a space in it cannot be
mistaken for two fields.

A field named `level` or `msg` replaces the one the object writes rather than
appearing twice: an object with a key twice is a document readers disagree
about, and the caller naming it meant it.

## What is checked

Every level against the filter in both directions; that `at` answers a new logger
rather than turning down the one everyone else is holding; that silence answers
no at all six levels and that the same logger with somewhere to write would have
written; the exact bytes of both formats, including a field that replaces the
message; every level's name parsing back, in every capitalisation, and a typo
answering `None`; and a sink of one's own receiving the record itself.

## Install

```bash
moon add moonbitstack/moonlog
```

## Licence

Apache-2.0.
