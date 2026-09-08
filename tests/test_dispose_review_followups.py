#!/usr/bin/env python3
"""Unit and contract tests for fixed|accepted|deferred triage."""
from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import dispose_review_followups as drf  # noqa: E402

MARKER = "<!-- themis-review-followups-disposed -->"
FP = "c0b1fd20198917df"


def review_item(text: str, kind: str = "risks") -> dict[str, str]:
    return {"kind": kind, "text": text}


class TestParseTriage(unittest.TestCase):
    def test_parses_list_and_normalizes_values(self) -> None:
        rows = drf.parse_triage(json.dumps([
            {"item": 1, "disposition": " FIXED ", "rationale": " commit abc  "},
            {"item": 2, "disposition": "deferred"},
        ]))
        self.assertEqual(rows[0], {
            "item": 1,
            "disposition": "fixed",
            "rationale": "commit abc",
        })
        self.assertEqual(rows[1]["disposition"], "deferred")

    def test_parses_items_object(self) -> None:
        rows = drf.parse_triage(json.dumps({
            "items": [{"item": 1, "disposition": "accepted", "rationale": "jsdom limit"}]
        }))
        self.assertEqual(len(rows), 1)

    def test_rejects_unknown_disposition(self) -> None:
        with self.assertRaisesRegex(drf.TriageError, r"fixed\|accepted\|deferred"):
            drf.parse_triage('[{"item": 1, "disposition": "ignored"}]')


class TestBuildPlan(unittest.TestCase):
    def test_builds_all_three_dispositions(self) -> None:
        items = [
            review_item("Missing regression assertion"),
            review_item("jsdom cannot verify computed pixels"),
            review_item("Broader cleanup can follow"),
        ]
        rows = drf.parse_triage(json.dumps([
            {"item": 1, "disposition": "fixed", "rationale": "commit abc123 adds assertion"},
            {"item": 2, "disposition": "accepted", "rationale": "class tokens are asserted; external STG remains oracle"},
            {"item": 3, "disposition": "deferred", "rationale": "requires product migration"},
        ]))
        plan = drf.build_plan(items, rows)
        self.assertEqual(plan["count"], 3)
        self.assertEqual(plan["deferred_count"], 1)
        self.assertEqual(
            [row["disposition"] for row in plan["items"]],
            ["fixed", "accepted", "deferred"],
        )

    def test_accept_without_rationale_fails(self) -> None:
        rows = drf.parse_triage('[{"item": 1, "disposition": "accepted"}]')
        with self.assertRaisesRegex(drf.TriageError, "accepted item 1 requires a rationale"):
            drf.build_plan([review_item("jsdom limitation")], rows)

    def test_fixed_without_commit_or_how_rationale_fails(self) -> None:
        rows = drf.parse_triage('[{"item": 1, "disposition": "fixed"}]')
        with self.assertRaisesRegex(drf.TriageError, "fixed item 1 requires a rationale"):
            drf.build_plan([review_item("missing assertion")], rows)

    def test_requires_exact_item_coverage(self) -> None:
        rows = drf.parse_triage(
            '[{"item": 1, "disposition": "deferred"},'
            '{"item": 3, "disposition": "deferred"}]'
        )
        with self.assertRaisesRegex(drf.TriageError, "missing items: 2; unknown items: 3"):
            drf.build_plan([review_item("one"), review_item("two")], rows)

    def test_accept_deny_list(self) -> None:
        denied = [
            "Security boundary is missing",
            "Authz check can be bypassed",
            "The ACL grants excess access",
            "A secret is exposed in logs",
            "The report uses invented metrics",
            "The request sends the wrong buildId",
            "This violates data honesty",
            "Logs contain PII",
            "OpenSpec says publish THEN implementation contradicts that rule",
        ]
        for text in denied:
            with self.subTest(text=text):
                rows = drf.parse_triage(
                    '[{"item": 1, "disposition": "accepted", "rationale": "known caveat"}]'
                )
                with self.assertRaisesRegex(drf.TriageError, "deny-listed"):
                    drf.build_plan([review_item(text)], rows)

    def test_documented_caveats_can_be_accepted(self) -> None:
        caveats = [
            "jsdom limits prevent layout measurement",
            "class-token validation is used instead of pixels",
            "testid wording differs from the FR",
            "<external-stg-oracle> remains oracle",
        ]
        for text in caveats:
            with self.subTest(text=text):
                rows = drf.parse_triage(json.dumps([
                    {"item": 1, "disposition": "accepted", "rationale": text}
                ]))
                plan = drf.build_plan([review_item(text)], rows)
                self.assertEqual(plan["items"][0]["disposition"], "accepted")


class TestArtifacts(unittest.TestCase):
    def test_dispose_body_has_structured_triage_marker_and_fingerprint(self) -> None:
        plan = {
            "items": [
                {
                    "item": 1,
                    "kind": "risks",
                    "text": "class-token | pixel caveat",
                    "disposition": "accepted",
                    "rationale": "<external-stg-oracle> remains oracle",
                }
            ]
        }
        body = drf.build_dispose_body(plan, MARKER, FP)
        self.assertIn(MARKER, body)
        self.assertIn(f"<!-- fingerprint={FP} -->", body)
        self.assertIn("| # | Review item | Disposition | Rationale |", body)
        self.assertIn("**accepted**", body)
        self.assertIn(r"class-token \| pixel caveat", body)

    def test_deferred_only_renders_for_existing_batch_path_and_dispose(self) -> None:
        items = [review_item("one"), review_item("two")]
        rows = drf.parse_triage(json.dumps([
            {"item": 1, "disposition": "deferred"},
            {"item": 2, "disposition": "deferred", "rationale": "same migration"},
        ]))
        plan = drf.build_plan(items, rows)
        deferred_review = drf.build_deferred_review(plan)
        self.assertEqual(deferred_review.count("\n- "), 2)
        body = drf.build_dispose_body(
            plan, MARKER, FP, issue_url="https://example.test/issues/9"
        )
        self.assertIn("one batched follow-up issue", body)
        self.assertEqual(body.count("https://example.test/issues/9"), 3)

    def test_mixed_plan_filters_fixed_and_accepted_from_deferred_review(self) -> None:
        plan = {
            "items": [
                {"item": 1, "kind": "risks", "text": "fixed", "disposition": "fixed", "rationale": "commit a"},
                {"item": 2, "kind": "risks", "text": "accepted", "disposition": "accepted", "rationale": "caveat"},
                {"item": 3, "kind": "risks", "text": "defer me", "disposition": "deferred", "rationale": ""},
            ]
        }
        rendered = drf.build_deferred_review(plan)
        self.assertNotIn("- fixed", rendered)
        self.assertNotIn("- accepted", rendered)
        self.assertIn("- defer me", rendered)


if __name__ == "__main__":
    unittest.main()
