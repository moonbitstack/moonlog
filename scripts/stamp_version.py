#!/usr/bin/env python3
"""The version the pages show is the one `moon.mod` declares.

A footer number typed by hand goes stale the first time the module moves, and
nothing notices: the site keeps saying what it said. This reads `version` from
`moon.mod` and writes it into every page under `docs/`, so the two cannot
disagree. The job runs it and fails on a diff, which is the only way a page can
be committed carrying a number that came from somewhere else.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PAGES = sorted((ROOT / "docs").glob("*.html"))

VER = re.compile(r'(<span class="ver">)[^<]*(</span>)')
FOOT = re.compile(r'(<span>moonlog )[^<]*( · Apache-2\.0</span>)')


def declared():
    """The version in `moon.mod`, which is the only place it is decided."""
    for line in (ROOT / "moon.mod").read_text(encoding="utf-8").splitlines():
        found = re.match(r'\s*version\s*=\s*"([^"]+)"', line)
        if found:
            return found.group(1)
    raise SystemExit("moon.mod declares no version")


def main():
    version = declared()
    touched = []
    for page in PAGES:
        before = page.read_text(encoding="utf-8")
        after = VER.sub(rf"\g<1>{version}\g<2>", before)
        after = FOOT.sub(rf"\g<1>{version}\g<2>", after)
        if after != before:
            page.write_text(after, encoding="utf-8", newline="\n")
            touched.append(page.name)
    print(f"{version}: {len(touched)} page(s) updated" + (f" ({', '.join(touched)})" if touched else ""))


if __name__ == "__main__":
    main()
