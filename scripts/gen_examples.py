#!/usr/bin/env python3
"""Turn the specification's own example documents into tests that read them.

`serlog-examples/` holds, verbatim, every configuration the logging
specification publishes as an example: the four YAML documents from its pages
and README, and the one its Rust example passes to `load_str`. This script
writes a test per document into `src/config/`, so a change to the specification
shows up as a diff rather than being retyped, and the documents are read by the
real reader rather than by a copy of it.

Each document carries what it is meant to mean, asserted key by key. The
document written with a sink kind this library does not ship is the case for a
refusal that names where it happened, and so is a document with a misspelt
setting.

CI only replays what is committed here; run this by hand after replacing the
documents:

    python3 scripts/gen_examples.py && moon fmt
"""

from pathlib import Path

EXAMPLES = Path(__file__).resolve().parent / "serlog-examples"
SRC = Path(__file__).resolve().parent.parent / "src" / "config"

HEADER = """// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The configuration examples the shared specification publishes, generated
/// from `scripts/serlog-examples/` by `scripts/gen_examples.py`: one test per
/// document, each asserting what the document says, key by key.
///
/// A document is a deployment's, so it is read with a lookup of its own: a
/// test that depended on the environment would pass or fail by whose machine
/// ran it.
fn example_env(name : String) -> String? {
  if name == "SMTP_PASS" {
    Some("s3cret")
  } else {
    None
  }
}

///|
/// A document read, or a test failure that says where the reader stopped.
fn example_read(document : String) -> Config raise {
  Config::parse(document, lookup=example_env) catch {
    error => fail("the document was refused at " + error.to_text())
  }
}

///|
/// The slot a document describes under `name`, or a failure naming the ones it
/// does describe.
fn example_slot(config : Config, name : String) -> Slot raise {
  match config.slot(name) {
    Some(slot) => slot
    None => {
      let names : Array[String] = []
      for slot in config.slots() {
        names.push(slot.name)
      }
      fail("no slot called " + name + ", only " + names.join(", "))
    }
  }
}
"""


def string(text):
    out = ['"']
    for char in text:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def raw(text):
    """The document as a MoonBit multiline string, one `#|` line at a time."""
    lines = text.rstrip("\n").split("\n")
    return "\n".join("    #|" + line for line in lines)


def slot_assertions(name, kind, settings, on_fail=None, alarm_only=False,
                    layout=None):
    out = []
    out.append(f'  let slot = example_slot(config, {string(name)})')
    out.append(f'  assert_eq(slot.kind, {string(kind)})')
    out.append(f'  assert_eq(slot.alarm_only, {str(alarm_only).lower()})')
    if on_fail is None:
        out.append("  assert_true(slot.on_fail is None)")
    else:
        out.append(f'  assert_eq(slot.on_fail, Some({string(on_fail)}))')
    if layout is None:
        out.append("  assert_true(slot.layout is None)")
    else:
        out.append(f'  assert_eq(slot.layout, Some({string(layout)}))')
    for kind_of, key, value in settings:
        if kind_of == "text":
            out.append(f'  assert_eq(slot.text({string(key)}), Some({string(value)}))')
        elif kind_of == "flag":
            out.append(
                f'  assert_eq(slot.flag({string(key)}), Some({str(value).lower()}))'
            )
        elif kind_of == "count":
            out.append(f'  assert_eq(slot.count({string(key)}), Some({value}))')
        elif kind_of == "size":
            out.append(f'  assert_eq(slot.size({string(key)}), Some({value}L))')
        elif kind_of == "span":
            out.append(f'  assert_eq(slot.span({string(key)}), Some({value}L))')
        elif kind_of == "pairs":
            joined = ", ".join(
                "(" + string(pair[0]) + ", " + string(pair[1]) + ")" for pair in value
            )
            out.append(f'  assert_eq(slot.pairs({string(key)}), Some([{joined}]))')
        elif kind_of == "texts":
            joined = ", ".join(string(item) for item in value)
            out.append(f'  assert_eq(slot.texts({string(key)}), Some([{joined}]))')
        else:
            raise ValueError(kind_of)
    return out


def document_test(name, source, body, assertions, refused_at=None, extra=None):
    lines = ["", "///|"]
    lines.append(f"/// {source}")
    lines.append(f'test "examples: {name}" {{')
    lines.append("  let document =")
    lines.append(raw(body))
    if refused_at is not None:
        lines.append("  let refused = try {")
        lines.append("    ignore(Config::parse(document, lookup=example_env))")
        lines.append("    None")
        lines.append("  } catch {")
        lines.append("    Refused(at~, ..) => Some(at)")
        lines.append("  }")
        lines.append(f"  assert_eq(refused, Some({string(refused_at)}))")
    else:
        lines.append("  let config = example_read(document)")
        lines.extend(assertions)
    if extra:
        lines.extend(extra)
    lines.append("}")
    return "\n".join(lines)


def main():
    config_page = (EXAMPLES / "config-page.yaml").read_text(encoding="utf-8")
    start_page = (EXAMPLES / "start-page.yaml").read_text(encoding="utf-8")
    failures_page = (EXAMPLES / "failures-page.yaml").read_text(encoding="utf-8")
    readme = (EXAMPLES / "readme.yaml").read_text(encoding="utf-8")
    phone = (EXAMPLES / "phone-example.yaml").read_text(encoding="utf-8")

    parts = [HEADER]

    # The page's own example: every key the format has, in one document.
    parts.append(
        document_test(
            "the config page's mirror deployment",
            "From the specification's config page: one of everything.",
            config_page,
            [
                '  assert_eq(config.app, "mirror")',
                '  assert_eq(config.env, "prod")',
                '  assert_eq(config.instance, "")',
                '  assert_eq(config.profile.name(), "serlog")',
                '  assert_eq(config.filter, "info,hustsync=debug")',
                "  assert_eq(config.levels.length(), 1)",
                '  assert_eq(config.levels[0].name, "notice")',
                "  assert_eq(config.levels[0].value, 35)",
                "  assert_true(config.levels[0].colour == @moonlog.Colour::Blue)",
                "  assert_eq(config.chain.length(), 2)",
                "  assert_eq(config.alarms.length(), 1)",
                '  assert_eq(config.alarms[0].0, "ops")',
                '  assert_eq(config.alarms[0].1.tiers, [["oncall"], ["stderr"]])',
                "  assert_eq(config.alarms[0].1.remind, 1_800_000_000_000L)",
                "  assert_true(config.alarms[0].1.fallback == @moonlog.Fallback::Panic)",
                "  assert_eq(config.watch, Some(30_000_000_000L))",
                "  assert_eq(config.slots().length(), 4)",
            ]
            + slot_assertions("console-1", "console", [])
            + slot_assertions(
                "app",
                "file",
                [
                    ("text", "path", "/var/log/app.log"),
                    ("size", "max_size", 67_108_864),
                    ("count", "keep", 7),
                    ("flag", "compress", True),
                ],
            )
            + slot_assertions(
                "loki-1",
                "loki",
                [("text", "url", "http://alloy:3100/loki/api/v1/push")],
                on_fail="ops",
            )
            + slot_assertions(
                "oncall",
                "mail",
                [
                    ("text", "host", "smtp.example.org"),
                    ("text", "username", "bot@example.org"),
                    ("text", "password", "s3cret"),
                    ("texts", "to", ["ops@example.org"]),
                ],
                alarm_only=True,
            ),
        )
    )

    # The start page: the shortest document a deployment writes.
    parts.append(
        document_test(
            "the start page's first deployment",
            "From the specification's start page: a console, a file and a shipper.",
            start_page,
            [
                '  assert_eq(config.app, "mirror")',
                '  assert_eq(config.env, "")',
                '  assert_eq(config.profile.name(), "serlog")',
                '  assert_eq(config.filter, "info,hustsync=debug")',
                "  assert_eq(config.chain.length(), 0)",
                "  assert_eq(config.alarms.length(), 0)",
                "  assert_true(config.watch is None)",
                "  assert_eq(config.slots().length(), 3)",
            ]
            + slot_assertions("console-1", "console", [])
            + slot_assertions(
                "app",
                "file",
                [
                    ("text", "path", "logs/app.log"),
                    ("span", "every", 86_400_000_000_000),
                    ("count", "keep", 7),
                    ("flag", "compress", True),
                ],
            )
            + slot_assertions(
                "loki-1",
                "loki",
                [
                    ("text", "url", "http://alloy:3100/loki/api/v1/push"),
                    ("pairs", "labels", [("team", "mirrors")]),
                ],
            ),
        )
    )

    # The failures page: an alarm with two tiers, a sink that points at it, and
    # one kept off the log route.
    parts.append(
        document_test(
            "the failures page's alarm",
            "From the specification's page on failures: an alarm and its route.",
            failures_page,
            [
                '  assert_eq(config.app, "")',
                "  assert_eq(config.alarms.length(), 1)",
                '  assert_eq(config.alarms[0].0, "ops")',
                '  assert_eq(config.alarms[0].1.tiers, [["oncall"], ["stderr"]])',
                "  assert_true(config.alarms[0].1.fallback == @moonlog.Fallback::Ignore)",
                "  assert_true(config.alarm is None)",
                "  assert_eq(config.slots().length(), 2)",
            ]
            + slot_assertions(
                "loki-1",
                "loki",
                [("text", "url", "http://alloy:3100/loki/api/v1/push")],
                on_fail="ops",
            )
            + slot_assertions(
                "oncall",
                "mail",
                [
                    ("text", "host", "smtp.example.org"),
                    ("texts", "to", ["ops@example.org"]),
                ],
                alarm_only=True,
            ),
        )
    )

    # The README's example: the one every language's README shows.
    parts.append(
        document_test(
            "the README's deployment",
            "From the specification's README, and the five language READMEs under it.",
            readme,
            [
                '  assert_eq(config.app, "mirror")',
                '  assert_eq(config.filter, "info,hustsync=debug")',
                "  assert_eq(config.chain.length(), 1)",
                "  assert_eq(config.watch, Some(30_000_000_000L))",
                '  assert_eq(config.alarms[0].1.tiers, [["stderr"]])',
                "  assert_eq(config.slots().length(), 3)",
            ]
            + slot_assertions("console-1", "console", [])
            + slot_assertions(
                "app",
                "file",
                [
                    ("text", "path", "/var/log/app.log"),
                    ("size", "max_size", 67_108_864),
                    ("count", "keep", 7),
                    ("flag", "compress", True),
                ],
            )
            + slot_assertions(
                "loki-1",
                "loki",
                [("text", "url", "http://alloy:3100/loki/api/v1/push")],
                on_fail="ops",
            ),
        )
    )

    # The Rust example registers a sink kind of its own; this library ships a
    # fixed set, so the document is refused where the kind is.
    parts.append(
        document_test(
            "the Rust example's own sink kind",
            "From the specification's Rust example, which registers a `phone` kind.",
            phone,
            None,
            refused_at="sinks.1.kind",
        )
    )

    # ... and so is a misspelt setting: the path is the whole point.
    parts.append(
        document_test(
            "a misspelt setting in the config page's document",
            "The config page's document with `max_size` written `max_sise`.",
            config_page.replace("max_size: 64MiB", "max_sise: 64MiB"),
            None,
            refused_at="sinks.1.max_sise",
        )
    )

    # A document read has to be a document that can be written back: a
    # deployment dumps what is in force to check it without the file.
    round_trip = ["", "///|"]
    round_trip.append(
        "/// The config page's document, written out in each format and read again."
    )
    round_trip.append('test "examples: a document written back reads the same" {')
    round_trip.append("  let document =")
    round_trip.append(raw(config_page))
    round_trip.append("  let config = example_read(document)")
    round_trip.append("  for format in [Format::Yaml, Format::Json, Format::Toml] {")
    round_trip.append("    let again = Config::parse(config.dump(format~), format~)")
    round_trip.append('    assert_eq(again.app(), "mirror")')
    round_trip.append('    assert_eq(again.env(), "prod")')
    round_trip.append('    assert_eq(again.filter(), "info,hustsync=debug")')
    round_trip.append('    assert_eq(again.profile().name(), "serlog")')
    round_trip.append("    assert_eq(again.levels().length(), 1)")
    round_trip.append("    assert_eq(again.chain().length(), 2)")
    round_trip.append("    assert_eq(again.process().length(), 2)")
    round_trip.append("    assert_eq(again.alarms().length(), 1)")
    round_trip.append("    assert_eq(again.watch_span(), Some(30_000_000_000L))")
    round_trip.append("    assert_eq(again.slots().length(), 4)")
    round_trip.append('    let file = example_slot(again, "app")')
    round_trip.append('    assert_eq(file.text("path"), Some("/var/log/app.log"))')
    round_trip.append('    assert_eq(file.size("max_size"), Some(67_108_864L))')
    round_trip.append('    assert_eq(file.flag("compress"), Some(true))')
    round_trip.append('    let loki = example_slot(again, "loki-1")')
    round_trip.append('    assert_eq(loki.on_fail, Some("ops"))')
    round_trip.append('    let mail = example_slot(again, "oncall")')
    round_trip.append("    assert_eq(mail.alarm_only, true)")
    round_trip.append("  }")
    round_trip.append("}")
    parts.append("\n".join(round_trip))

    (SRC / "examples_wbtest.mbt").write_text(
        "\n".join(parts), encoding="utf-8", newline="\n"
    )
    print("wrote src/config/examples_wbtest.mbt")


if __name__ == "__main__":
    main()
