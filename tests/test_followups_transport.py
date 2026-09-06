#!/usr/bin/env python3
"""Contract tests for followups_transport (no live APIs)."""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import unittest
import unittest.mock
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

spec = importlib.util.spec_from_file_location(
    "followups_transport", ROOT / "scripts" / "followups_transport.py"
)
assert spec and spec.loader
ft = importlib.util.module_from_spec(spec)
sys.modules["followups_transport"] = ft
spec.loader.exec_module(ft)

REVIEW_MARKER = "<!-- themis-cursor-review -->"
DISPOSE_MARKER = "<!-- themis-review-followups-disposed -->"


class TestSelectLatestReview(unittest.TestCase):
    def test_picks_last_matching_comment(self) -> None:
        comments = [
            {"id": 1, "body": "noise"},
            {"id": 2, "body": f"old review {REVIEW_MARKER}"},
            {"id": 3, "body": f"latest review {REVIEW_MARKER} with Risks"},
        ]
        body = ft.select_latest_themis_review(comments, REVIEW_MARKER)
        self.assertIn("latest review", body or "")
        self.assertIn("Risks", body or "")

    def test_no_marker_returns_none(self) -> None:
        self.assertIsNone(ft.select_latest_themis_review([{"body": "x"}], REVIEW_MARKER))


class TestFindDispose(unittest.TestCase):
    def test_matches_marker_and_fingerprint(self) -> None:
        fp = "c0b1fd20198917df"
        comments = [
            {"id": 10, "body": f"{DISPOSE_MARKER}\n<!-- fingerprint=other -->"},
            {"id": 11, "body": f"{DISPOSE_MARKER}\n<!-- fingerprint={fp} -->\ndone"},
        ]
        self.assertEqual(ft.find_dispose_comment(comments, DISPOSE_MARKER, fp), "11")

    def test_no_match(self) -> None:
        self.assertIsNone(
            ft.find_dispose_comment(
                [{"id": 1, "body": DISPOSE_MARKER}], DISPOSE_MARKER, "abc"
            )
        )


class TestJiraPayload(unittest.TestCase):
    def test_batched_shape_with_epic_parent(self) -> None:
        payload = ft.build_jira_create_payload(
            project_key="RQ",
            summary="Themis follow-ups (PR #30): 2 items",
            description="## Checklist\n\n- [ ] **risks:** foo",
            labels=["themis-followup", "impl-dev", "solark"],
            epic_key="RQ-2000",
            issue_type="Task",
        )
        fields = payload["fields"]
        self.assertEqual(fields["project"]["key"], "RQ")
        self.assertEqual(fields["parent"]["key"], "RQ-2000")
        self.assertEqual(fields["labels"], ["themis-followup", "impl-dev", "solark"])
        self.assertEqual(fields["issuetype"]["name"], "Task")
        self.assertEqual(fields["description"]["type"], "doc")
        self.assertIn("Checklist", fields["description"]["content"][0]["content"][0]["text"])


class TestConfig(unittest.TestCase):
    def test_defaults_github(self) -> None:
        env = os.environ.copy()
        for k in list(env):
            if k.startswith(("THEMIS_FOLLOWUP_", "BITBUCKET_", "JIRA_")):
                del env[k]
        with unittest.mock.patch.dict(os.environ, env, clear=True):
            cfg = ft.FollowUpConfig.from_env()
        self.assertEqual(cfg.tracker, "github")
        self.assertEqual(cfg.scm, "github")

    def test_bb_repo_slug_from_env(self) -> None:
        with unittest.mock.patch.dict(
            os.environ,
            {
                "THEMIS_FOLLOWUP_SCM": "bitbucket",
                "THEMIS_FOLLOWUP_BB_REPO": "sol-ark/ai-support-agent",
            },
            clear=False,
        ):
            cfg = ft.FollowUpConfig.from_env()
        self.assertEqual(cfg.bb_workspace, "sol-ark")
        self.assertEqual(cfg.bb_repo_slug, "ai-support-agent")
        url = cfg.source_pr_url(30)
        self.assertEqual(
            url, "https://bitbucket.org/sol-ark/ai-support-agent/pull-requests/30"
        )


class TestTransportFixtures(unittest.TestCase):
    def test_bb_comment_list_and_dispose(self) -> None:
        fp = "deadbeef01234567"
        bb_page = {
            "values": [
                {"id": 100, "content": {"raw": f"review {REVIEW_MARKER}\n## Risks\n- x"}},
                {"id": 101, "content": {"raw": "unrelated"}},
            ],
            "next": None,
        }

        def fake_request(method: str, url: str, headers, body):
            if method == "GET" and "comments" in url:
                return 200, json.dumps(bb_page)
            if method == "POST" and "comments" in url:
                return 201, json.dumps({"id": 999})
            return 404, "{}"

        cfg = ft.FollowUpConfig(
            scm="bitbucket",
            bb_workspace="ws",
            bb_repo_slug="repo",
            bb_username="u",
            bb_token="t",
        )
        t = ft.FollowUpTransport(config=cfg, request_fn=fake_request)
        review = t.fetch_latest_review(5, REVIEW_MARKER)
        self.assertIn("Risks", review or "")
        self.assertIsNone(t.find_disposed(5, DISPOSE_MARKER, fp))
        bb_page["values"].append(
            {
                "id": 102,
                "content": {
                    "raw": f"{DISPOSE_MARKER}\n<!-- fingerprint={fp} -->"
                },
            }
        )
        self.assertEqual(t.find_disposed(5, DISPOSE_MARKER, fp), "102")
        cid = t.post_dispose_comment(5, f"{DISPOSE_MARKER}\n<!-- fingerprint={fp} -->")
        self.assertEqual(cid, "999")

    def test_jira_file_one_issue(self) -> None:
        captured: dict = {}

        def fake_request(method: str, url: str, headers, body):
            captured["method"] = method
            captured["url"] = url
            captured["body"] = json.loads(body.decode()) if body else None
            return 201, json.dumps({"key": "RQ-2381"})

        cfg = ft.FollowUpConfig(
            tracker="jira",
            jira_base_url="https://example.atlassian.net",
            jira_email="a@b.c",
            jira_api_token="tok",
            jira_project_key="RQ",
            jira_epic="RQ-2000",
            jira_extra_labels=("solark",),
        )
        t = ft.FollowUpTransport(config=cfg, request_fn=fake_request)
        url = t.file_batched_issue(
            title="Themis follow-ups",
            body="checklist",
            pr=30,
            default_labels=["themis-followup", "impl-dev"],
        )
        self.assertEqual(url, "https://example.atlassian.net/browse/RQ-2381")
        fields = captured["body"]["fields"]
        self.assertEqual(fields["parent"]["key"], "RQ-2000")
        self.assertEqual(
            fields["labels"], ["themis-followup", "impl-dev", "solark"]
        )


if __name__ == "__main__":
    unittest.main()
