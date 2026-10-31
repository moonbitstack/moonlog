"""Write docs/api.html from the generated interfaces and the `///` comments in
the sources, so the reference follows the code. Usage, from the repository
root, after `moon info --target all`: python scripts/gen_api.py

The root package is grouped by what a name does; each subpackage is a section of
its own, because a reader looking for `File::new` already knows which package it
is in. Both halves go through the same reader, so a type and its methods stay
together wherever they are declared."""
import html
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
GROUPS = [
    ("levels", "Levels", ["level", "colour"]),
    ("values", "Values and records", ["value", "record"]),
    ("errors", "Errors", ["error"]),
    ("filters", "Filters", ["filter"]),
    ("steps", "Steps", ["processor"]),
    ("layouts", "Layouts", ["layout", "pattern", "json", "text", "time"]),
    ("sinks", "Sinks", ["sink"]),
    ("slots", "Slots and health", ["slot", "breaker"]),
    ("alarms", "Alarms", ["alarm"]),
    ("hub", "Hub and logger", ["hub", "logger", "scene"]),
    ("profiles", "Profiles", ["profile"]),
]
PACKAGES = [
    ("stdio", "stdio", "A console on standard output, standard error, or both"),
    ("file", "file", "A file that rotates itself"),
    ("loki", "loki", "Entries pushed to Loki"),
    ("mail", "mail", "Records mailed as one letter"),
    ("config", "config", "A document read, checked and written back"),
    ("global", "global", "The process-wide hub"),
]
DECL = re.compile(
    r"^pub(?:\((?:all|open)\))?\s+(?:fn(?:\[[^\]]*\])?|let|struct|enum|suberror|trait|type)\s+"
    r"([A-Za-z_]\w*(?:::[A-Za-z_]\w*)?)"
)
BOILERPLATE = re.compile(r"::(equal|not_equal|output|to_string|to_repr|hash|compare|op_\w+)\(")
TRAIT = re.compile(r"^pub(?:\((?:all|open)\))?\s+trait\s+(\w+)")


def sources(base):
    """Doc comments and the declaring file, by declared name."""
    docs, home = {}, {}
    for path in sorted(base.glob("*.mbt")):
        if path.name.endswith(("_test.mbt", "_wbtest.mbt")):
            continue
        pending, trait = [], None
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if trait and line.startswith("}"):
                trait = None
            if stripped == "///|":
                pending = []
            elif stripped.startswith("///"):
                pending.append(stripped[3:].strip())
            elif trait and stripped.startswith("fn "):
                method = re.match(r"fn (\w+)", stripped).group(1)
                if pending:
                    docs[f"{trait}::{method}"] = " ".join(pending)
                pending = []
            else:
                opened = TRAIT.match(line)
                if opened and line.rstrip().endswith("{"):
                    trait = opened.group(1)
                match = DECL.match(line)
                if match:
                    home[match.group(1)] = path.stem
                    if pending:
                        docs[match.group(1)] = " ".join(pending)
                pending = []
    return docs, home


def items(mbti):
    """(kind, name, rest, owner) for each public item, in interface order."""
    out, block = [], None
    for line in mbti.read_text(encoding="utf-8").splitlines():
        if block is not None:
            if line.startswith("}"):
                body = [b for b in block[2] if not b.startswith("//")]
                sep = " · " if block[0] in ("enum", "suberror") else ", "
                out.append(("type" if block[0] != "trait" else "trait", block[1], sep.join(body), None))
                block = None
            else:
                block[2].append(line.strip())
            continue
        if line.startswith("#") or BOILERPLATE.search(line):
            continue
        m = re.match(r"pub(?:\((?:all|open)\))?\s+(struct|enum|suberror|trait)\s+(\w+)", line)
        if m:
            if line.rstrip().endswith("{"):
                block = [m.group(1), m.group(2), []]
            else:
                out.append(("type", m.group(2), "", None))
            continue
        m = re.match(r"pub fn(?:\[[^\]]*\])? (\w+)::(\w+)(.*)$", line)
        if m:
            out.append(("fn", f"{m.group(1)}::{m.group(2)}", m.group(3), m.group(1)))
            continue
        m = re.match(r"pub fn(?:\[[^\]]*\])? (\w+)(.*)$", line)
        if m:
            out.append(("fn", m.group(1), m.group(2), None))
            continue
        m = re.match(r"pub let (\w+) : (.*)$", line)
        if m:
            out.append(("let", m.group(1), m.group(2), None))
            continue
        m = re.match(r"pub impl (?:@\w+\.)?(\w+) for (\w+)", line)
        if m:
            out.append(("impl", m.group(1), "", m.group(2)))
    return out


def prose(text):
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", html.escape(text, quote=False))


def block_for(name, rest, doc, kind, impls):
    if kind == "type" and impls.get(name):
        doc = (doc + " " if doc else "") + "Implements " + ", ".join(f"`{t}`" for t in impls[name]) + "."
    words = " ".join([name, name.split("::")[-1], re.sub(r"[^A-Za-z0-9_ ]", " ", doc).lower()])
    label = {"type": "ty", "trait": "ty", "fn": "fn", "let": "fn"}[kind]
    shown = {"type": "type", "trait": "trait", "fn": "fn", "let": "let"}[kind]
    return (
        f'        <div class="entry" data-api-entry="{html.escape(words)}">\n'
        f'          <div class="sig"><span class="kind {label}">{shown}</span>'
        f'<span class="name">{html.escape(name)}</span><span class="rest">{html.escape(rest.strip())}</span></div>\n'
        + (f'          <p class="what">{prose(doc)}</p>\n' if doc else "")
        + "        </div>"
    )


def grouped(listed, docs, impls):
    """Entries as blocks: a type followed by its methods, then what stands alone."""
    types, loose = {}, []
    for kind, name, rest, owner in listed:
        if kind == "impl":
            continue
        doc = docs.get(name, "")
        if not doc and owner:
            method = name.split("::")[1]
            for t in impls.get(owner, []):
                if f"{t}::{method}" in docs:
                    doc = f"As a `{t}`: " + docs[f"{t}::{method}"]
                    break
        block = block_for(name, rest, doc, kind, impls)
        if kind in ("type", "trait"):
            types.setdefault(name, []).insert(0, block)
        elif owner:
            types.setdefault(owner, []).append(block)
        else:
            loose.append(block)
    body = []
    for name in sorted(types):
        body.extend(types[name])
    body.extend(loose)
    return body


def impls_of(listed):
    impls = {}
    for kind, name, _, owner in listed:
        if kind == "impl":
            impls.setdefault(owner, []).append(name)
    return impls


def render():
    body = []
    listed = items(SRC / "pkg.generated.mbti")
    impls = impls_of(listed)
    docs, home = sources(SRC)
    entries = {key: {"types": {}, "loose": []} for key, _, _ in GROUPS}
    group_of = {stem: key for key, _, stems in GROUPS for stem in stems}
    for kind, name, rest, owner in listed:
        if kind == "impl":
            continue
        stem = home.get(name) or home.get(owner or "", "")
        key = group_of.get(stem, "hub")
        doc = docs.get(name, "")
        if not doc and owner:
            method = name.split("::")[1]
            for t in impls.get(owner, []):
                if f"{t}::{method}" in docs:
                    doc = f"As a `{t}`: " + docs[f"{t}::{method}"]
                    break
        block = block_for(name, rest, doc, kind, impls)
        if kind in ("type", "trait"):
            entries[key]["types"].setdefault(name, []).insert(0, block)
        elif owner:
            entries[key]["types"].setdefault(owner, []).append(block)
        else:
            entries[key]["loose"].append(block)
    for key, title, _ in GROUPS:
        body.append(f'        <h2 id="{key}" data-api-group>{title}</h2>\n')
        for name in sorted(entries[key]["types"]):
            body.extend(entries[key]["types"][name])
        body.extend(entries[key]["loose"])
        body.append("")
    for key, title, blurb in PACKAGES:
        package = SRC / key
        body.append(
            f'        <h2 id="{key}" data-api-group>moonlog/{html.escape(title)}</h2>\n'
            f'        <p class="note">{html.escape(blurb)}.</p>\n'
        )
        package_listed = items(package / "pkg.generated.mbti")
        package_docs, _ = sources(package)
        body.extend(grouped(package_listed, package_docs, impls_of(package_listed)))
        body.append("")

    rail = [f'        <a href="#{key}">{html.escape(title)}</a>' for key, title, _ in GROUPS]
    rail.append('        <div class="group">Subpackages</div>')
    rail += [f'        <a href="#{key}">moonlog/{html.escape(title)}</a>' for key, title, _ in PACKAGES]

    page = (ROOT / "docs" / "api.template.html").read_text(encoding="utf-8")
    page = page.replace("<!-- body -->", "\n".join(body))
    page = page.replace("<!-- rail -->", "\n".join(rail))
    (ROOT / "docs" / "api.html").write_text(page, encoding="utf-8", newline="\n")


render()
