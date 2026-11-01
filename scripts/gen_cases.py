#!/usr/bin/env python3
"""Turn the shared specification's cases into MoonBit tests.

`serlog-cases/` holds the three case files of the logging specification
(ServerLog, MIT) exactly as published: `render.json`, `fail.json` and
`alarm.json`. This script reads them and writes one MoonBit test per case into
`src/`, named with the case's number, so the cases are replayed rather than
retyped and a change to the specification shows up as a diff in one place.

CI only replays what is committed here; run this by hand after replacing the
files:

    python3 scripts/gen_cases.py && moon fmt
"""

from pathlib import Path
import json

CASES = Path(__file__).resolve().parent / "serlog-cases"
SRC = Path(__file__).resolve().parent.parent / "src"

HEADER = """// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0
"""

PROFILES = {
    "serlog": "Serlog",
    "tracing": "Tracing",
    "env_logger": "EnvLogger",
    "python": "Python",
    "logback": "Logback",
    "slog": "Slog",
    "pino": "Pino",
}


def text(value):
    """A MoonBit string literal for `value`."""
    out = ['"']
    for char in value:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif char == "\r":
            out.append("\\r")
        else:
            out.append(char)
    out.append('"')
    return "".join(out)


def value(item):
    """A `Value` literal for a field as the case file writes it."""
    if item is None:
        return "@moonlog.Value::Null"
    if item is True:
        return "@moonlog.Value::of_bool(true)"
    if item is False:
        return "@moonlog.Value::of_bool(false)"
    if isinstance(item, int):
        return "@moonlog.Value::of_long(" + str(item) + "L)"
    if isinstance(item, float):
        return "@moonlog.Value::of_float(" + repr(item) + ")"
    if isinstance(item, str):
        return "@moonlog.Value::of_str(" + text(item) + ")"
    if isinstance(item, list):
        return "@moonlog.Value::of_list([" + ", ".join(value(x) for x in item) + "])"
    if "$error" in item:
        parts = item["$error"]
        causes = ", ".join(text(cause) for cause in parts[1:])
        return (
            "@moonlog.Value::of_error(message="
            + text(parts[0])
            + ", causes=["
            + causes
            + "])"
        )
    pairs = ", ".join("(" + text(key) + ", " + value(x) + ")" for key, x in item.items())
    return "@moonlog.Value::of_map([" + pairs + "])"


def json_text(item):
    """The text a JSON line writes for `item`, for an expectation."""
    return text(json.dumps(item, separators=(",", ":"), ensure_ascii=False))


def names(items):
    return "[" + ", ".join(text(item) for item in items) + "]"


def render_file(cases):
    out = [HEADER]
    out.append(
        """
///|
/// The render cases of the shared specification, generated from
/// `scripts/serlog-cases/render.json` by `scripts/gen_cases.py`: one test per
/// case, named with the case's number. Patterns, presets, logfmt, pretty, the
/// JSON schemas and the filters all come from the same record and identity.
fn spec_identity() -> @moonlog.Identity {
  @moonlog.Identity::of(app="demo", env="prod", instance="n1", host="box")
}

///|
/// A scene with the identity the cases share, seen through `profile`.
fn spec_scene(profile : @moonlog.Profile) -> @moonlog.Scene {
  @moonlog.Scene::new(identity=spec_identity(), profile~)
}

///|
/// Where `needle` first stands in `line`.
fn spec_find(line : String, needle : String) -> Int? {
  let chars = line.to_array()
  let pattern = needle.to_array()
  if pattern.length() == 0 || pattern.length() > chars.length() {
    return None
  }
  for start in 0..=(chars.length() - pattern.length()) {
    let mut same = true
    for offset in 0..<pattern.length() {
      if chars[start + offset] != pattern[offset] {
        same = false
      }
    }
    if same {
      return Some(start)
    }
  }
  None
}

///|
/// The value `key` holds in the JSON object `line`, as the text between its
/// colons and the comma or brace that ends it.
fn spec_value(line : String, key : String) -> String? {
  let start = match spec_find(line, "\\"" + key + "\\":") {
    Some(at) => at + key.length() + 3
    None => return None
  }
  let chars = line.to_array()
  let out = StringBuilder()
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  let mut reading = true
  let mut at = start
  while at < chars.length() && reading {
    let char = chars[at]
    if in_string {
      out.write_char(char)
      if escaped {
        escaped = false
      } else if char == '\\\\' {
        escaped = true
      } else if char == '"' {
        in_string = false
      }
    } else if char == '"' {
      in_string = true
      out.write_char(char)
    } else if char == '{' || char == '[' {
      depth = depth + 1
      out.write_char(char)
    } else if char == '}' || char == ']' {
      if depth == 0 {
        reading = false
      } else {
        depth = depth - 1
        out.write_char(char)
      }
    } else if char == ',' && depth == 0 {
      reading = false
    } else {
      out.write_char(char)
    }
    at = at + 1
  }
  Some(out.to_string())
}

///|
/// Whether a piece of JSON text is a number.
fn spec_is_number(item : String) -> Bool {
  let chars = item.to_array()
  if chars.length() == 0 {
    return false
  }
  let first = chars[0]
  first == '-' || (first >= '0' && first <= '9')
}

///|
/// Two numbers as the same number, whatever the precision they were written
/// with: a case says `1700000000.0` where a line writes `1700000000.000`.
fn spec_same_number(one : String, other : String) -> Bool {
  fn whole(item : String) -> (String, String) {
    let (sign, body) = if item.has_prefix("-") {
      ("-", item[1:].to_owned())
    } else {
      ("", item)
    }
    match body.find(".") {
      Some(dot) => (sign + body[:dot].to_owned(), body[dot + 1:].to_owned())
      None => (sign + body, "")
    }
  }
  let (one_whole, one_part) = whole(one)
  let (other_whole, other_part) = whole(other)
  let mut one_rest = one_part
  let mut other_rest = other_part
  while one_rest.has_suffix("0") {
    one_rest = one_rest[:one_rest.length() - 1].to_owned()
  }
  while other_rest.has_suffix("0") {
    other_rest = other_rest[:other_rest.length() - 1].to_owned()
  }
  one_whole == other_whole && one_rest == other_rest
}

///|
/// Whether `key` holds `want` in the JSON object `line`. Numbers compare by
/// value; everything else compares as the very text a JSON writer emits.
fn spec_holds(line : String, key : String, want : String) -> Bool {
  match spec_value(line, key) {
    None => false
    Some(got) =>
      if spec_is_number(want) && spec_is_number(got) {
        spec_same_number(got, want)
      } else {
        got == want
      }
  }
}

///|
/// Whether `keys` appear in `line` in this order, each one a key of the object
/// rather than a word inside a value.
fn spec_in_order(line : String, keys : Array[String]) -> Bool {
  let mut last = -1
  for key in keys {
    let at = match spec_find(line, "\\"" + key + "\\":") {
      Some(at) => at
      None => return false
    }
    if at <= last {
      return false
    }
    last = at
  }
  true
}
"""
    )

    for number, case in enumerate(cases["cases"], start=1):
        record = case["record"]
        out.append("\n///|\n")
        out.append(
            'test "render.json '
            + str(number)
            + ": "
            + record["level"]
            + " from "
            + record["target"]
            + '" {\n'
        )
        out.append(
            "  let record = @moonlog.Record::of("
            + "@moonlog.Level::parse("
            + text(record["level"])
            + "), "
            + text(record["target"])
            + ", "
            + text(record["msg"])
            + ")\n"
        )
        if "file" in record:
            out.append(
                "  .located("
                + text(record["file"])
                + ", line="
                + str(record["line"])
                + ")\n"
            )
        if record.get("fields"):
            out.append("  .sets([\n")
            for name, item in record["fields"]:
                out.append("    (" + text(name) + ", " + value(item) + "),\n")
            out.append("  ])\n")
        out.append(
            "  .stamped("
            + str(record["time"])
            + "L * 1_000_000_000L)\n"
        )
        out.append(
            "  let scene = spec_scene(@moonlog.Profile::Serlog)\n"
        )
        for pattern in case.get("patterns", []):
            out.append("  assert_eq(\n")
            out.append(
                "    @moonlog.Pattern::parse("
                + text(pattern["pattern"])
                + ").render(record, scene),\n"
            )
            out.append("    " + text(pattern["expect"]) + ",\n")
            out.append("  )\n")
        for preset in case.get("presets", []):
            profile = PROFILES[preset["name"]]
            out.append("  // The " + preset["name"] + " preset.\n")
            call = (
                "    @moonlog.Pattern::parse("
                + text(preset["name"])
                + ").render(record, spec_scene(@moonlog.Profile::"
                + profile
                + "))"
            )
            if "expect" in preset:
                out.append("  assert_eq(\n")
                out.append(call + ",\n")
                out.append("    " + text(preset["expect"]) + ",\n")
                out.append("  )\n")
            else:
                out.append("  assert_true(\n")
                out.append(call + ".has_suffix(" + text(preset["tail"]) + "),\n")
                out.append("  )\n")
        if "logfmt" in case:
            out.append(
                "  assert_eq(\n"
                "    @moonlog.Logfmt::new().render(record, scene),\n"
                "    "
                + text(case["logfmt"])
                + ",\n"
                "  )\n"
            )
        if "pretty" in case:
            # The case file gives the tail of the pretty layout, not the whole
            # line: the time at the head of it depends on the reader's zone.
            out.append(
                "  assert_true(\n"
                "    @moonlog.Pretty::new().render(record, scene).has_suffix(\n"
                "      "
                + text(case["pretty"])
                + ",\n"
                "    ),\n"
                "  )\n"
            )
        if "json" in case:
            out.append(
                "  assert_eq(\n"
                "    @moonlog.JsonLine::new(@moonlog.Schema::Serlog).render(record, scene),\n"
                "    "
                + text(case["json"])
                + ",\n"
                "  )\n"
            )
        for schema in case.get("schemas", []):
            out.append("  // The " + schema["schema"] + " schema.\n")
            out.append(
                "  let "
                + schema["schema"].replace(".", "_")
                + " = @moonlog.JsonLine::new(@moonlog.Schema::parse("
                + text(schema["schema"])
                + ")).render(record, scene)\n"
            )
            out.append(
                "  assert_true(spec_in_order("
                + schema["schema"].replace(".", "_")
                + ", "
                + names(schema["keys"])
                + "))\n"
            )
            for key, want in schema["has"].items():
                out.append(
                    "  assert_true(spec_holds("
                    + schema["schema"].replace(".", "_")
                    + ", "
                    + text(key)
                    + ", "
                    + json_text(want)
                    + "))\n"
                )
        out.append("}\n")

    for number, case in enumerate(cases["filters"], start=1):
        spec = case["spec"]
        out.append("\n///|\n")
        out.append(
            'test "render.json filter '
            + str(number)
            + ": "
            + (spec if spec else "an empty spec")
            + '" {\n'
        )
        out.append("  let filter = @moonlog.Filter::parse(" + text(spec) + ")\n")
        allowed = case.get("messages", {}).get("allow", [])
        denied = case.get("messages", {}).get("deny", [])
        for index, (level, target) in enumerate(case["allow"]):
            msg = allowed[index % len(allowed)] if allowed else ""
            out.append(
                "  assert_true(\n"
                "    filter.admits(@moonlog.Level::parse("
                + text(level)
                + "), "
                + text(target)
                + ", "
                + text(msg)
                + "),\n"
                "  )\n"
            )
        for index, (level, target) in enumerate(case["deny"]):
            msg = denied[index % len(denied)] if denied else ""
            out.append(
                "  assert_false(\n"
                "    filter.admits(@moonlog.Level::parse("
                + text(level)
                + "), "
                + text(target)
                + ", "
                + text(msg)
                + "),\n"
                "  )\n"
            )
        out.append("}\n")
    return "".join(out)


def fail_file(cases):
    out = [HEADER]
    out.append(
        """
///|
/// The health cases of the shared specification, generated from
/// `scripts/serlog-cases/fail.json` by `scripts/gen_cases.py`: one test per
/// case, named with the case's number. Each step happens at a given second,
/// the sink says whether the write went through, and the machine must answer
/// whether it was tried, where it stands and what it told.
///
/// | step | machine |
/// |:--|:--|
/// | `up` fails | `down`, `opened` when told, next probe after `probe` |
/// | `down` before its probe | skipped, not tried |
/// | `down` at its probe | `probing`, one write decides |
/// | `probing` passes | `up`, `resolved` when the failure was told |
/// | `probing` fails | `down`, the wait doubled up to five minutes, `reminder` once `remind` has passed |
fn spec_nanos(seconds : Double) -> Int64 {
  (seconds * 1_000_000_000.0).to_int64()
}

///|
/// One step: the write goes ahead when the machine admits it, the sink answers
/// as `fails` says, and the phase the machine reports comes back.
fn spec_step(
  breaker : @moonlog.Breaker,
  at : Double,
  fails : Bool,
  remind : Double,
  tell : @moonlog.Tell,
) -> (Bool, @moonlog.Phase?) {
  let now = spec_nanos(at)
  let tried = breaker.admit(now)
  let phase = if !tried {
    None
  } else if fails {
    breaker.fault(now, "broken", spec_nanos(remind), tell)
  } else {
    breaker.pass(now)
  }
  (tried, phase)
}
"""
    )
    for number, case in enumerate(cases["cases"], start=1):
        tell = {"report": "Report", "silent": "Silent", "folded": "Folded"}[
            case["tell"]
        ]
        out.append("\n///|\n")
        out.append(
            'test "fail.json '
            + str(number)
            + ": "
            + case["name"]
            + '" {\n'
        )
        out.append(
            "  let breaker = @moonlog.Breaker::new(spec_nanos("
            + repr(float(case["probe"]))
            + "), 0L)\n"
        )
        for step in case["steps"]:
            fails = step["result"] == "err"
            out.append(
                "  let (tried, phase) = spec_step(breaker, "
                + repr(float(step["at"]))
                + ", "
                + ("true" if fails else "false")
                + ", "
                + repr(float(case["remind"]))
                + ", @moonlog.Tell::"
                + tell
                + ")\n"
            )
            out.append(
                "  assert_eq(tried, " + ("true" if step["tried"] else "false") + ")\n"
            )
            out.append(
                "  assert_eq(phase, "
                + (
                    "None"
                    if step["phase"] is None
                    else "Some(@moonlog.Phase::"
                    + step["phase"].capitalize()
                    + ")"
                )
                + ")\n"
            )
            out.append(
                "  assert_eq(breaker.health(), @moonlog.Health::"
                + step["health"].capitalize()
                + ")\n"
            )
        out.append("  assert_eq(breaker.skipped(), " + str(case["skipped"]) + "L)\n")
        out.append("}\n")
    return "".join(out)


def alarm_file(cases):
    out = [HEADER]
    out.append(
        """
///|
/// The alarm cases of the shared specification, generated from
/// `scripts/serlog-cases/alarm.json` by `scripts/gen_cases.py`: one test per
/// case, named with the case's number. The failing sink is never asked, `*`
/// stands for every sink on the log route, a resting sink is left out, and one
/// success ends the walk.
struct SpecStand {
  logs : Array[String]
  down : Array[String]
  results : Map[String, Bool]
  asked : Array[String]
}

///|
fn spec_stand(
  logs : Array[String],
  down : Array[String],
  results : Array[(String, Bool)],
) -> SpecStand {
  let answers : Map[String, Bool] = Map([])
  for pair in results {
    answers[pair.0] = pair.1
  }
  { logs, down, results: answers, asked: [], }
}

///|
pub impl @moonlog.Desk for SpecStand with fn logs(self) {
  self.logs
}

///|
pub impl @moonlog.Desk for SpecStand with fn resting(self, name) {
  self.down.contains(name)
}

///|
pub impl @moonlog.Desk for SpecStand with fn deliver(self, name, _record) {
  self.asked.push(name)
  match self.results.get(name) {
    Some(true) => Ok(())
    _ => Err("refused")
  }
}

///|
/// One walk: what the alarm made of the incident, which sinks it asked, and
/// which failures the incident ended up carrying.
fn spec_walk(
  failing : String,
  tiers : Array[Array[String]],
  stand : SpecStand,
) -> (@moonlog.Outcome, Array[String], Array[String]) {
  let incident = @moonlog.Incident::new(
    failing,
    "sink",
    @moonlog.Phase::Opened,
    "broken",
    0L,
  )
  let outcome = @moonlog.sound(@moonlog.Tiers::from(tiers), incident, stand)
  let failures : Array[String] = []
  for failure in incident.failures {
    failures.push(failure.sink)
  }
  (outcome, stand.asked, failures)
}
"""
    )
    for number, case in enumerate(cases["cases"], start=1):
        out.append("\n///|\n")
        out.append(
            'test "alarm.json ' + str(number) + ": " + case["name"] + '" {\n'
        )
        answers = ", ".join(
            "(" + text(name) + ", " + ("true" if answer == "ok" else "false") + ")"
            for name, answer in case["results"].items()
        )
        out.append(
            "  let stand = spec_stand("
            + names(case["logs"])
            + ", "
            + names(case["down"])
            + ", ["
            + answers
            + "])\n"
        )
        tiers = ", ".join(names(tier) for tier in case["tiers"])
        out.append(
            "  let (outcome, asked, failures) = spec_walk("
            + text(case["failing"])
            + ", ["
            + tiers
            + "], stand)\n"
        )
        out.append(
            "  assert_eq(outcome, @moonlog.Outcome::"
            + case["outcome"].capitalize()
            + ")\n"
        )
        flattened = [name for tier in case["tried"] for name in tier]
        out.append("  assert_eq(asked, " + names(flattened) + ")\n")
        out.append("  assert_eq(failures, " + names(case["failures"]) + ")\n")
        out.append("}\n")
    return "".join(out)


def main():
    render = json.loads((CASES / "render.json").read_text(encoding="utf-8"))
    fail = json.loads((CASES / "fail.json").read_text(encoding="utf-8"))
    alarm = json.loads((CASES / "alarm.json").read_text(encoding="utf-8"))
    written = {
        SRC / "spec_render_test.mbt": render_file(render),
        SRC / "spec_fail_test.mbt": fail_file(fail),
        SRC / "spec_alarm_test.mbt": alarm_file(alarm),
    }
    for path, body in written.items():
        path.write_text(body, encoding="utf-8", newline="\n")
        print("wrote", path.relative_to(SRC.parent))


if __name__ == "__main__":
    main()
