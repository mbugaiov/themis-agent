#!/usr/bin/env python3
"""Parse Themis/Cursor review follow-up sections (Suggestions / High priority / Risks / …).

Source of truth for all dual-review engines. Engines set:

  THEMIS_REVIEW_MARKER          HTML marker in the review comment
  THEMIS_FOLLOWUP_SECTIONS      comma-separated ## titles (default below)
  THEMIS_FOLLOWUP_DISPOSE_MARKER  disposal comment marker (shell scripts)

Does not fail CI by itself — engines gate merge via check_review_followups_disposed.sh.
"""
from __future__ import annotations

import json
import os
import re
import sys

DEFAULT_SECTIONS = (
    "Suggestions",
    "High priority issues",
    "Risks",
)

ITEM_LINE = re.compile(
    r"^\s*(?:[-*]|\d+\.)\s+(?:\*\*.*?\*\*\s*[—:-]\s*)?(.+\S)\s*$"
)


def section_titles() -> tuple[str, ...]:
    raw = os.environ.get("THEMIS_FOLLOWUP_SECTIONS", "").strip()
    if raw:
        return tuple(s.strip() for s in raw.split(",") if s.strip())
    return DEFAULT_SECTIONS


def review_marker() -> str:
    return os.environ.get(
        "THEMIS_REVIEW_MARKER",
        "<!-- themis-cursor-review -->",
    ).strip() or "<!-- themis-cursor-review -->"


def extract_section(text: str, title: str) -> str | None:
    lines = text.split("\n")
    in_section = False
    body: list[str] = []
    header = re.compile(rf"^## {re.escape(title)}\s*$", re.I)
    for line in lines:
        if header.match(line):
            in_section = True
            continue
        if in_section and re.match(r"^## ", line):
            break
        if in_section:
            body.append(line)
    if not in_section:
        return None
    return "\n".join(body).strip()


def section_is_empty(section: str | None) -> bool:
    if section is None:
        return True
    if not section.strip():
        return True
    for line in section.split("\n"):
        s = line.strip()
        if not s:
            continue
        return bool(re.match(r"^None\.?\s*$", s, re.I))
    return True


def parse_items(section: str | None, kind: str) -> list[dict[str, str]]:
    if section_is_empty(section):
        return []
    assert section is not None
    items: list[dict[str, str]] = []
    buf: list[str] = []

    def flush() -> None:
        nonlocal buf
        if not buf:
            return
        text = " ".join(x.strip() for x in buf if x.strip())
        buf = []
        if text:
            items.append({"kind": kind, "text": text})

    for line in section.split("\n"):
        if re.match(r"^\s*(?:[-*]|\d+\.)\s+", line):
            flush()
            m = ITEM_LINE.match(line)
            buf = [m.group(1) if m else line.strip()]
        elif buf and line.strip():
            buf.append(line.strip())
        elif not line.strip():
            flush()
    flush()
    if not items and section.strip() and not re.match(r"^None\.?\s*$", section, re.I):
        items.append({"kind": kind, "text": " ".join(section.split())})
    return items


def extract_followups(text: str, titles: tuple[str, ...] | None = None) -> list[dict[str, str]]:
    out: list[dict[str, str]] = []
    for title in titles or section_titles():
        kind = title.lower().replace(" ", "-")
        out.extend(parse_items(extract_section(text, title), kind))
    return out


def fingerprint(items: list[dict[str, str]]) -> str:
    import hashlib

    blob = "\n".join(f"{i['kind']}:{i['text']}" for i in items)
    if not blob:
        return "empty"
    return hashlib.sha256(blob.encode()).hexdigest()[:16]


def format_batched_issue_body(
    items: list[dict[str, str]],
    *,
    pr: str | int,
    repo: str,
    fp: str | None = None,
    pr_url: str | None = None,
) -> str:
    """One backlog issue body: single checklist for all gated follow-ups."""
    count = len(items)
    fp = fp if fp is not None else fingerprint(items)
    source_url = pr_url or f"https://github.com/{repo}/pull/{pr}"
    lines = [
        f"## From Themis review on PR #{pr}",
        "",
        f"**Source PR:** {source_url}",
        f"**Fingerprint:** `{fp}`",
        f"**Items:** {count}",
        "",
        "Fix **all** checklist items in **one** follow-up PR (do not open one PR per bullet).",
        "",
        "### Checklist",
        "",
    ]
    for it in items:
        kind = (it.get("kind") or "Follow-up").strip()
        # parse_items joins wrapped bullets with spaces — one checklist line per item.
        text = " ".join((it.get("text") or "").split()) or "(empty)"
        lines.append(f"- [ ] **{kind}:** {text}")
        lines.append("")
    lines.extend(
        [
            "---",
            "",
            "Filed by themis-agent `file_review_followups.sh` (batched) — pick up via `themis-followup` / `backlog`.",
        ]
    )
    return "\n".join(lines)


def fetch_latest_themis_review(
    repo: str, pr: int, marker: str | None = None
) -> str | None:
    """Fetch latest review comment from SCM (GitHub default; Bitbucket when env set)."""
    import importlib.util
    from dataclasses import replace
    from pathlib import Path

    marker = marker or review_marker()
    transport_path = Path(__file__).with_name("followups_transport.py")
    spec = importlib.util.spec_from_file_location("followups_transport", transport_path)
    if not spec or not spec.loader:
        raise RuntimeError("followups_transport.py not found")
    ft = importlib.util.module_from_spec(spec)
    # dataclasses need the module registered before exec_module (CPython importlib).
    sys.modules["followups_transport"] = ft
    spec.loader.exec_module(ft)
    cfg = ft.FollowUpConfig.from_env()
    if repo and not cfg.github_repo:
        cfg = replace(cfg, github_repo=repo)
    transport = ft.FollowUpTransport(config=cfg)
    return transport.fetch_latest_review(pr, marker)


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(
            "Usage: review_followups.py <review.md> [--json|--issue-body]\n"
            "       review_followups.py --from-pr <PR> --repo owner/name [--json|--issue-body]\n"
            "       --issue-body requires --pr N --repo owner/name (renders one batched checklist)\n"
            "       --fingerprint FP optionally preserves the source review fingerprint\n"
            "Env: THEMIS_REVIEW_MARKER, THEMIS_FOLLOWUP_SECTIONS",
            file=sys.stderr,
        )
        return 2
    as_json = "--json" in sys.argv
    as_issue_body = "--issue-body" in sys.argv
    if as_json and as_issue_body:
        print("Use only one of --json / --issue-body", file=sys.stderr)
        return 2
    issue_pr = None
    issue_repo = None

    def _flag_value(flag: str) -> str | None:
        if flag not in sys.argv:
            return None
        i = sys.argv.index(flag)
        if i + 1 >= len(sys.argv) or sys.argv[i + 1].startswith("-"):
            print(f"{flag} requires a value", file=sys.stderr)
            return ""
        return sys.argv[i + 1]

    issue_pr = _flag_value("--pr")
    issue_repo = _flag_value("--repo")
    issue_fingerprint = _flag_value("--fingerprint")
    if issue_pr == "" or issue_repo == "" or issue_fingerprint == "":
        return 2
    if sys.argv[1] == "--from-pr":
        if len(sys.argv) < 3:
            return 2
        pr = int(sys.argv[2])
        repo = issue_repo
        if not repo:
            import subprocess

            repo = (
                subprocess.check_output(
                    ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]
                )
                .decode()
                .strip()
            )
        issue_pr = issue_pr or str(pr)
        issue_repo = repo
        text = fetch_latest_themis_review(repo, pr) or ""
        if not text:
            print("NO_REVIEW", file=sys.stderr)
            return 1
    else:
        path = sys.argv[1]
        text = open(path, encoding="utf-8").read()
    items = extract_followups(text)
    if as_issue_body:
        if not issue_pr or not issue_repo:
            print("--issue-body requires --pr N and --repo owner/name", file=sys.stderr)
            return 2
        pr_url = None
        try:
            import importlib.util
            from pathlib import Path

            tp = Path(__file__).with_name("followups_transport.py")
            spec = importlib.util.spec_from_file_location("followups_transport", tp)
            if spec and spec.loader:
                ft = importlib.util.module_from_spec(spec)
                sys.modules["followups_transport"] = ft
                spec.loader.exec_module(ft)
                cfg = ft.FollowUpConfig.from_env()
                pr_url = cfg.source_pr_url(issue_pr)
        except Exception:
            pr_url = None
        print(
            format_batched_issue_body(
                items,
                pr=issue_pr,
                repo=issue_repo,
                fp=issue_fingerprint,
                pr_url=pr_url,
            )
        )
    elif as_json:
        print(
            json.dumps(
                {
                    "count": len(items),
                    "items": items,
                    "fingerprint": fingerprint(items),
                    "sections": list(section_titles()),
                    "marker": review_marker(),
                },
                ensure_ascii=False,
                indent=2,
            )
        )
    else:
        if not items:
            print("FOLLOWUPS_NONE")
            return 0
        for i, it in enumerate(items, 1):
            print(f"{i}. [{it['kind']}] {it['text']}")
        print(f"FOLLOWUPS_COUNT {len(items)}")
        print(f"FOLLOWUPS_FP {fingerprint(items)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
