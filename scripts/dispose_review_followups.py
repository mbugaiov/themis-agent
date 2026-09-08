#!/usr/bin/env python3
"""Validate per-item Themis follow-up triage and build disposal artifacts."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

import review_followups

DISPOSITIONS = {"fixed", "accepted", "deferred"}

# Accepted means a documented caveat, never a waiver for correctness or safety.
ACCEPT_DENY_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("security/authz/ACL/secrets", re.compile(
        r"\b(security|authz|authori[sz]ation|access control|acl|secret(?:s)?|credential(?:s)?)\b",
        re.I,
    )),
    ("invented metrics / wrong buildId", re.compile(
        r"\b(invent(?:ed|ing)?\s+(?:metrics?|numbers?|scores?)|fabricat(?:ed|ing)\s+(?:metrics?|numbers?|scores?)|wrong\s+build\s*id|build\s*id\s+(?:is\s+)?(?:wrong|incorrect|mismatch))\b",
        re.I,
    )),
    ("data honesty", re.compile(
        r"\b(data honesty|misleading data|fabricat(?:ed|ing)\s+data|fals(?:e|ified)\s+data)\b",
        re.I,
    )),
    ("PII", re.compile(r"\bpii\b|personally identifiable information", re.I)),
    ("OpenSpec THEN contradiction", re.compile(
        r"(?:openspec.{0,120}\bthen\b.{0,120}contradict|\bthen\b.{0,120}openspec.{0,120}contradict|openspec.{0,120}contradict.{0,120}\bthen\b)",
        re.I,
    )),
)


class TriageError(ValueError):
    """Invalid or unsafe triage input."""


def parse_triage(raw: str) -> list[dict[str, Any]]:
    """Parse a JSON list (or {"items": [...]}) of item dispositions."""
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise TriageError(f"triage must be valid JSON: {exc.msg}") from exc
    if isinstance(payload, dict):
        payload = payload.get("items")
    if not isinstance(payload, list):
        raise TriageError("triage must be a JSON list or an object with an 'items' list")

    rows: list[dict[str, Any]] = []
    for position, row in enumerate(payload, 1):
        if not isinstance(row, dict):
            raise TriageError(f"triage row {position} must be an object")
        item = row.get("item")
        if isinstance(item, bool) or not isinstance(item, int) or item < 1:
            raise TriageError(f"triage row {position} has invalid positive integer 'item'")
        disposition = str(row.get("disposition") or "").strip().lower()
        if disposition not in DISPOSITIONS:
            raise TriageError(
                f"triage item {item} disposition must be fixed|accepted|deferred"
            )
        rationale = " ".join(str(row.get("rationale") or "").split())
        rows.append(
            {"item": item, "disposition": disposition, "rationale": rationale}
        )
    return rows


def acceptance_denial_reason(text: str) -> str | None:
    for reason, pattern in ACCEPT_DENY_PATTERNS:
        if pattern.search(text):
            return reason
    return None


def build_plan(
    review_items: list[dict[str, str]], triage_rows: list[dict[str, Any]]
) -> dict[str, Any]:
    """Validate exact item coverage and enrich rows with review text."""
    expected = set(range(1, len(review_items) + 1))
    actual = [int(row["item"]) for row in triage_rows]
    if len(actual) != len(set(actual)):
        raise TriageError("each review item must appear exactly once; duplicate item found")
    missing = sorted(expected - set(actual))
    extra = sorted(set(actual) - expected)
    if missing or extra:
        details = []
        if missing:
            details.append(f"missing items: {', '.join(map(str, missing))}")
        if extra:
            details.append(f"unknown items: {', '.join(map(str, extra))}")
        raise TriageError("triage must cover every review item exactly once (" + "; ".join(details) + ")")

    by_item = {int(row["item"]): row for row in triage_rows}
    result: list[dict[str, Any]] = []
    for index, review_item in enumerate(review_items, 1):
        row = by_item[index]
        disposition = str(row["disposition"])
        rationale = str(row["rationale"])
        if disposition in {"fixed", "accepted"} and not rationale:
            raise TriageError(f"{disposition} item {index} requires a rationale")
        if disposition == "accepted":
            denial = acceptance_denial_reason(review_item.get("text") or "")
            if denial:
                raise TriageError(
                    f"accepted item {index} is deny-listed ({denial}); fix or defer it"
                )
        result.append(
            {
                "item": index,
                "kind": review_item.get("kind") or "follow-up",
                "text": review_item.get("text") or "",
                "disposition": disposition,
                "rationale": rationale,
            }
        )
    return {
        "items": result,
        "count": len(result),
        "fingerprint": review_followups.fingerprint(review_items),
        "deferred_count": sum(1 for row in result if row["disposition"] == "deferred"),
    }


def _escape_table(value: str) -> str:
    return " ".join(value.split()).replace("|", r"\|")


def build_dispose_body(
    plan: dict[str, Any],
    dispose_marker: str,
    fingerprint: str,
    *,
    issue_url: str = "",
) -> str:
    """Build a structured disposal comment while preserving marker + fingerprint."""
    lines = [
        dispose_marker,
        f"<!-- fingerprint={fingerprint} -->",
        "## Themis follow-ups disposed",
        "",
        "| # | Review item | Disposition | Rationale |",
        "|---:|---|---|---|",
    ]
    for row in plan.get("items") or []:
        rationale = str(row.get("rationale") or "")
        if row.get("disposition") == "deferred" and issue_url:
            rationale = f"{rationale + '; ' if rationale else ''}batched at {issue_url}"
        lines.append(
            f"| {row['item']} | **{_escape_table(str(row['kind']))}:** "
            f"{_escape_table(str(row['text']))} | **{row['disposition']}** | "
            f"{_escape_table(rationale) or '—'} |"
        )
    if issue_url:
        lines.extend(
            [
                "",
                f"Deferred items were filed as one batched follow-up issue: {issue_url}",
            ]
        )
    return "\n".join(lines)


def build_deferred_review(plan: dict[str, Any]) -> str:
    """Render only deferred items for the existing batched filing path."""
    sections: dict[str, list[str]] = {}
    for row in plan.get("items") or []:
        if row.get("disposition") != "deferred":
            continue
        title = str(row.get("kind") or "follow-up").replace("-", " ").title()
        sections.setdefault(title, []).append(str(row.get("text") or ""))
    lines: list[str] = []
    for title, items in sections.items():
        lines.append(f"## {title}")
        lines.extend(f"- {text}" for text in items)
        lines.append("")
    return "\n".join(lines).rstrip() + ("\n" if lines else "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    plan_parser = sub.add_parser("plan", help="validate triage and write normalized plan")
    plan_parser.add_argument("review_file")
    plan_parser.add_argument("triage_file")
    plan_parser.add_argument("--output", required=True)
    plan_parser.add_argument("--deferred-review")

    body_parser = sub.add_parser("body", help="build structured dispose comment")
    body_parser.add_argument("plan_file")
    body_parser.add_argument("--marker", required=True)
    body_parser.add_argument("--fingerprint", required=True)
    body_parser.add_argument("--issue-url", default="")

    args = parser.parse_args()
    try:
        if args.command == "plan":
            review_text = Path(args.review_file).read_text(encoding="utf-8")
            triage_text = Path(args.triage_file).read_text(encoding="utf-8")
            items = review_followups.extract_followups(review_text)
            plan = build_plan(items, parse_triage(triage_text))
            Path(args.output).write_text(
                json.dumps(plan, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            if args.deferred_review:
                Path(args.deferred_review).write_text(
                    build_deferred_review(plan), encoding="utf-8"
                )
            print(json.dumps(
                {
                    "count": plan["count"],
                    "deferred_count": plan["deferred_count"],
                    "fingerprint": plan["fingerprint"],
                }
            ))
            return 0

        plan = json.loads(Path(args.plan_file).read_text(encoding="utf-8"))
        print(build_dispose_body(
            plan, args.marker, args.fingerprint, issue_url=args.issue_url
        ))
        return 0
    except (OSError, TriageError, json.JSONDecodeError) as exc:
        print(f"TRIAGE_ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
