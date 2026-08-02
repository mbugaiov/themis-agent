#!/usr/bin/env python3
"""Parse Themis review / isolation output for blocking issues."""
from __future__ import annotations

import re
import sys

LGTM_LINE = re.compile(r"^LGTM - no blocking issues found\.?\s*$", re.I)


def is_lgtm_only(text: str) -> bool:
    trimmed = text.strip()
    return bool(trimmed) and "\n" not in trimmed and bool(LGTM_LINE.match(trimmed))


def extract_blocking_section(text: str) -> str | None:
    lines = text.split("\n")
    in_section = False
    body: list[str] = []
    for line in lines:
        if re.match(r"^## Blocking issues\s*$", line, re.I):
            in_section = True
            continue
        if in_section and re.match(r"^## ", line):
            break
        if in_section:
            body.append(line)
    if not in_section:
        return None
    return "\n".join(body).strip()


def review_has_blockers(text: str) -> bool:
    trimmed = text.strip()
    if not trimmed:
        return True
    if is_lgtm_only(trimmed):
        return False
    section = extract_blocking_section(text)
    if section is None:
        return True
    if re.match(r"^None\.?\s*$", section, re.I):
        return False
    if not section:
        return True
    return True


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else "review.md"
    text = open(path, encoding="utf-8").read()
    if review_has_blockers(text):
        section = extract_blocking_section(text)
        print("Review gate FAILED — blocking issues found:", file=sys.stderr)
        if section:
            print(section, file=sys.stderr)
        return 1
    print("Review gate: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
