#!/usr/bin/env python3
"""Env-driven SCM + tracker transport for Themis follow-ups (GitHub default).

SCM (where review/dispose comments live):
  THEMIS_FOLLOWUP_SCM=github|bitbucket  (default github)

Tracker (where batched backlog issues are filed):
  THEMIS_FOLLOWUP_TRACKER=github|jira   (default github)

Bitbucket env: BITBUCKET_WORKSPACE, BITBUCKET_REPO_SLUG (or THEMIS_FOLLOWUP_BB_REPO=ws/slug),
  BITBUCKET_USERNAME, BITBUCKET_APP_PASSWORD or BITBUCKET_TOKEN

Jira env: JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY,
  THEMIS_FOLLOWUP_JIRA_EPIC, optional THEMIS_FOLLOWUP_JIRA_LABELS (comma-separated)
"""
from __future__ import annotations

import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, replace
from typing import Any, Callable


RequestFn = Callable[[str, str, dict[str, str] | None, bytes | None], tuple[int, str]]


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _normalize_tracker(raw: str) -> str:
    v = (raw or "github").lower()
    if v not in ("github", "jira"):
        raise ValueError(f"THEMIS_FOLLOWUP_TRACKER must be github|jira, got {raw!r}")
    return v


def _normalize_scm(raw: str) -> str:
    v = (raw or "github").lower()
    if v not in ("github", "bitbucket"):
        raise ValueError(f"THEMIS_FOLLOWUP_SCM must be github|bitbucket, got {raw!r}")
    return v


@dataclass(frozen=True)
class FollowUpConfig:
    tracker: str = "github"
    scm: str = "github"
    github_repo: str = ""
    bb_workspace: str = ""
    bb_repo_slug: str = ""
    bb_username: str = ""
    bb_token: str = ""
    jira_base_url: str = ""
    jira_email: str = ""
    jira_api_token: str = ""
    jira_project_key: str = ""
    jira_epic: str = ""
    jira_extra_labels: tuple[str, ...] = field(default_factory=tuple)

    @classmethod
    def from_env(cls) -> FollowUpConfig:
        bb_ws = _env("BITBUCKET_WORKSPACE")
        bb_slug = _env("BITBUCKET_REPO_SLUG")
        bb_repo = _env("THEMIS_FOLLOWUP_BB_REPO")
        if bb_repo and "/" in bb_repo:
            parts = bb_repo.split("/", 1)
            bb_ws = bb_ws or parts[0]
            bb_slug = bb_slug or parts[1]

        extra = tuple(
            s.strip()
            for s in _env("THEMIS_FOLLOWUP_JIRA_LABELS", "").split(",")
            if s.strip()
        )
        bb_token = _env("BITBUCKET_TOKEN") or _env("BITBUCKET_APP_PASSWORD")

        return cls(
            tracker=_normalize_tracker(_env("THEMIS_FOLLOWUP_TRACKER", "github")),
            scm=_normalize_scm(_env("THEMIS_FOLLOWUP_SCM", "github")),
            github_repo=_env("THEMIS_FOLLOWUP_REPO") or _env("GITHUB_REPOSITORY"),
            bb_workspace=bb_ws,
            bb_repo_slug=bb_slug,
            bb_username=_env("BITBUCKET_USERNAME"),
            bb_token=bb_token,
            jira_base_url=_env("JIRA_BASE_URL").rstrip("/"),
            jira_email=_env("JIRA_EMAIL") or _env("BITBUCKET_USERNAME"),
            jira_api_token=_env("JIRA_API_TOKEN") or _env("ATLASSIAN_TOKEN"),
            jira_project_key=_env("JIRA_PROJECT_KEY"),
            jira_epic=_issue_key_from(_env("THEMIS_FOLLOWUP_JIRA_EPIC")),
            jira_extra_labels=extra,
        )

    def source_pr_url(self, pr: int | str) -> str:
        if self.scm == "bitbucket":
            if not self.bb_workspace or not self.bb_repo_slug:
                raise RuntimeError(
                    "Bitbucket SCM requires BITBUCKET_WORKSPACE + BITBUCKET_REPO_SLUG "
                    "or THEMIS_FOLLOWUP_BB_REPO=workspace/slug"
                )
            return (
                f"https://bitbucket.org/{self.bb_workspace}/"
                f"{self.bb_repo_slug}/pull-requests/{pr}"
            )
        repo = self.github_repo
        if not repo:
            raise RuntimeError("GitHub SCM requires THEMIS_FOLLOWUP_REPO or GITHUB_REPOSITORY")
        return f"https://github.com/{repo}/pull/{pr}"


def _issue_key_from(value: str) -> str:
    if not value:
        return ""
    return value.rstrip("/").split("/")[-1].strip()


def select_latest_themis_review(
    comments: list[dict[str, Any]], marker: str
) -> str | None:
    """Return body of the latest comment containing *marker* (list order = API order)."""
    matches = [
        str(c.get("body") or "")
        for c in comments
        if marker in str(c.get("body") or "")
    ]
    return matches[-1] if matches else None


def find_dispose_comment(
    comments: list[dict[str, Any]], dispose_marker: str, fingerprint: str
) -> str | None:
    """Return comment id when dispose marker + fingerprint already present."""
    fp_tag = f"fingerprint={fingerprint}"
    for c in comments:
        body = str(c.get("body") or "")
        if dispose_marker in body and fp_tag in body:
            cid = c.get("id")
            return str(cid) if cid is not None else "1"
    return None


def build_dispose_body(
    dispose_marker: str,
    fingerprint: str,
    *,
    filed: bool = False,
    issue_url: str = "",
    count: int = 0,
) -> str:
    if filed and issue_url:
        return (
            f"{dispose_marker}\n"
            f"<!-- fingerprint={fingerprint} -->\n"
            "## Themis follow-ups disposed\n\n"
            "Follow-ups from review were filed as **one** backlog issue (not fixed in this PR).\n"
            "Pick up and fix **all** checklist items in a **single** PR:\n\n"
            f"- {issue_url}\n\n"
            "Label: `themis-followup` / `backlog` (or Jira equivalents)."
        )
    return (
        f"{dispose_marker}\n"
        f"<!-- fingerprint={fingerprint} -->\n"
        "## Themis follow-ups disposed\n\n"
        "No follow-up items to file (or sections are `None.`)."
    )


def build_jira_create_payload(
    *,
    project_key: str,
    summary: str,
    description: str,
    labels: list[str],
    epic_key: str = "",
    issue_type: str = "Task",
) -> dict[str, Any]:
    """One batched Jira issue under epic (parent) when epic_key set."""
    fields: dict[str, Any] = {
        "project": {"key": project_key},
        "summary": summary,
        "description": _plain_text_to_adf(description),
        "issuetype": {"name": issue_type},
        "labels": labels,
    }
    if epic_key:
        fields["parent"] = {"key": epic_key}
    return {"fields": fields}


def _plain_text_to_adf(text: str) -> dict[str, Any]:
    """Minimal ADF document from plain/markdown-ish text (one paragraph per block)."""
    blocks: list[dict[str, Any]] = []
    for chunk in re.split(r"\n\s*\n", text.strip()):
        if not chunk.strip():
            continue
        lines = [ln for ln in chunk.split("\n") if ln.strip()]
        content: list[dict[str, Any]] = []
        for i, ln in enumerate(lines):
            if i:
                content.append({"type": "hardBreak"})
            content.append({"type": "text", "text": ln})
        blocks.append({"type": "paragraph", "content": content})
    if not blocks:
        blocks = [{"type": "paragraph", "content": [{"type": "text", "text": text}]}]
    return {"type": "doc", "version": 1, "content": blocks}


def _basic_auth_header(user: str, secret: str) -> str:
    token = base64.b64encode(f"{user}:{secret}".encode()).decode()
    return f"Basic {token}"


def _urllib_request(
    method: str, url: str, headers: dict[str, str] | None, body: bytes | None
) -> tuple[int, str]:
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, resp.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


@dataclass
class FollowUpTransport:
    config: FollowUpConfig
    request_fn: RequestFn = _urllib_request
    gh_api_fn: Callable[..., str] | None = None

    def _gh_api(self, path: str) -> str:
        if self.gh_api_fn:
            return self.gh_api_fn(path)
        return subprocess.check_output(
            ["gh", "api", path], stderr=subprocess.DEVNULL
        ).decode()

    def _gh_api_post(self, path: str, body: dict[str, Any]) -> str:
        if self.gh_api_fn:
            return self.gh_api_fn(path, method="POST", body=body)
        raw = subprocess.check_output(
            ["gh", "api", path, "-f", f"body={body['body']}"],
            stderr=subprocess.DEVNULL,
        ).decode()
        return raw

    def _bb_auth_headers(self) -> dict[str, str]:
        if not self.config.bb_username or not self.config.bb_token:
            raise RuntimeError(
                "Bitbucket requires BITBUCKET_USERNAME + "
                "BITBUCKET_TOKEN (or BITBUCKET_APP_PASSWORD)"
            )
        return {
            "Authorization": _basic_auth_header(
                self.config.bb_username, self.config.bb_token
            ),
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def _bb_path(self, pr: int | str, suffix: str = "comments") -> str:
        ws, slug = self.config.bb_workspace, self.config.bb_repo_slug
        if not ws or not slug:
            raise RuntimeError(
                "Bitbucket SCM requires BITBUCKET_WORKSPACE + BITBUCKET_REPO_SLUG"
            )
        return (
            f"https://api.bitbucket.org/2.0/repositories/{ws}/{slug}/"
            f"pullrequests/{pr}/{suffix}"
        )

    def list_scm_comments(self, pr: int | str) -> list[dict[str, Any]]:
        if self.config.scm == "bitbucket":
            return self._list_bb_comments(pr)
        return self._list_gh_comments(pr)

    def fetch_latest_review(self, pr: int | str, marker: str) -> str | None:
        return select_latest_themis_review(self.list_scm_comments(pr), marker)

    def find_disposed(self, pr: int | str, dispose_marker: str, fp: str) -> str | None:
        return find_dispose_comment(self.list_scm_comments(pr), dispose_marker, fp)

    def post_dispose_comment(self, pr: int | str, body: str) -> str:
        if self.config.scm == "bitbucket":
            return self._post_bb_comment(pr, body)
        return self._post_gh_comment(pr, body)

    def file_batched_issue(
        self, *, title: str, body: str, pr: int | str, default_labels: list[str]
    ) -> str:
        if self.config.tracker == "jira":
            return self._file_jira_issue(title=title, body=body, default_labels=default_labels)
        return self._file_github_issue(title=title, body=body, default_labels=default_labels)

    def _list_gh_comments(self, pr: int | str) -> list[dict[str, Any]]:
        repo = self.config.github_repo
        if not repo:
            repo = (
                subprocess.check_output(
                    ["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"]
                )
                .decode()
                .strip()
            )
            object.__setattr__(self, "config", replace(self.config, github_repo=repo))
        comments: list[dict[str, Any]] = []
        page = 1
        while True:
            path = f"repos/{repo}/issues/{pr}/comments?per_page=100&page={page}"
            batch = json.loads(self._gh_api(path))
            if not batch:
                break
            for c in batch:
                comments.append({"id": c.get("id"), "body": c.get("body") or ""})
            if len(batch) < 100:
                break
            page += 1
        return comments

    def _list_bb_comments(self, pr: int | str) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        url: str | None = self._bb_path(pr) + "?pagelen=100"
        headers = self._bb_auth_headers()
        while url:
            status, raw = self.request_fn("GET", url, headers, None)
            if status >= 400:
                raise RuntimeError(f"Bitbucket list comments HTTP {status}: {raw[:300]}")
            page = json.loads(raw)
            for row in page.get("values") or []:
                out.append(
                    {
                        "id": row.get("id"),
                        "body": (row.get("content") or {}).get("raw") or "",
                    }
                )
            url = page.get("next")
        return out

    def _post_gh_comment(self, pr: int | str, body: str) -> str:
        repo = self.config.github_repo
        if not repo:
            raise RuntimeError("GitHub SCM requires THEMIS_FOLLOWUP_REPO")
        path = f"repos/{repo}/issues/{pr}/comments"
        self._gh_api_post(path, {"body": body})
        return "posted"

    def _post_bb_comment(self, pr: int | str, body: str) -> str:
        url = self._bb_path(pr)
        payload = json.dumps({"content": {"raw": body}}).encode()
        status, raw = self.request_fn("POST", url, self._bb_auth_headers(), payload)
        if status >= 400:
            raise RuntimeError(f"Bitbucket post comment HTTP {status}: {raw[:300]}")
        row = json.loads(raw)
        return str(row.get("id") or "posted")

    def _file_github_issue(self, *, title: str, body: str, default_labels: list[str]) -> str:
        repo = self.config.github_repo
        if not repo:
            raise RuntimeError("GitHub tracker requires THEMIS_FOLLOWUP_REPO")
        label_args: list[str] = []
        for lb in default_labels:
            label_args.extend(["--label", lb])
        cmd = ["gh", "issue", "create", "-R", repo, "--title", title, "--body", body]
        cmd.extend(label_args)
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode()
        except subprocess.CalledProcessError:
            out = subprocess.check_output(
                ["gh", "issue", "create", "-R", repo, "--title", title, "--body", body]
            ).decode()
        return out.strip().splitlines()[-1].strip()

    def _file_jira_issue(self, *, title: str, body: str, default_labels: list[str]) -> str:
        cfg = self.config
        if not all(
            [cfg.jira_base_url, cfg.jira_email, cfg.jira_api_token, cfg.jira_project_key]
        ):
            raise RuntimeError(
                "Jira tracker requires JIRA_BASE_URL, JIRA_EMAIL, JIRA_API_TOKEN, JIRA_PROJECT_KEY"
            )
        labels = list(dict.fromkeys(default_labels + list(cfg.jira_extra_labels)))
        payload = build_jira_create_payload(
            project_key=cfg.jira_project_key,
            summary=title,
            description=body,
            labels=labels,
            epic_key=cfg.jira_epic,
        )
        url = f"{cfg.jira_base_url}/rest/api/3/issue"
        headers = {
            "Authorization": _basic_auth_header(cfg.jira_email, cfg.jira_api_token),
            "Accept": "application/json",
            "Content-Type": "application/json",
        }
        status, raw = self.request_fn(
            "POST", url, headers, json.dumps(payload).encode()
        )
        if status >= 400:
            raise RuntimeError(f"Jira create issue HTTP {status}: {raw[:500]}")
        key = json.loads(raw).get("key") or ""
        if not key:
            raise RuntimeError(f"Jira create issue missing key: {raw[:200]}")
        return f"{cfg.jira_base_url}/browse/{key}"


def transport_from_env() -> FollowUpTransport:
    return FollowUpTransport(config=FollowUpConfig.from_env())


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description="Themis follow-ups SCM/tracker transport")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_fetch = sub.add_parser("fetch-review", help="Fetch latest Themis review body from SCM")
    p_fetch.add_argument("pr", type=int)
    p_fetch.add_argument("--marker", required=True)

    p_find = sub.add_parser("find-dispose", help="Find dispose comment id for fingerprint")
    p_find.add_argument("pr", type=int)
    p_find.add_argument("--marker", required=True)
    p_find.add_argument("--fingerprint", required=True)

    p_post = sub.add_parser("post-dispose", help="Post dispose marker comment on SCM PR")
    p_post.add_argument("pr", type=int)
    p_post.add_argument("--body-file", required=True)

    p_file = sub.add_parser("file-issue", help="File one batched backlog issue")
    p_file.add_argument("--title", required=True)
    p_file.add_argument("--body-file", required=True)
    p_file.add_argument("--label", action="append", default=[])

    p_cfg = sub.add_parser("config", help="Print resolved transport config (JSON)")

    args = ap.parse_args()
    t = transport_from_env()

    if args.cmd == "config":
        c = t.config
        print(
            json.dumps(
                {
                    "tracker": c.tracker,
                    "scm": c.scm,
                    "github_repo": c.github_repo,
                    "bb_workspace": c.bb_workspace,
                    "bb_repo_slug": c.bb_repo_slug,
                    "jira_project_key": c.jira_project_key,
                    "jira_epic": c.jira_epic,
                    "jira_extra_labels": list(c.jira_extra_labels),
                },
                indent=2,
            )
        )
        return 0

    if args.cmd == "fetch-review":
        body = t.fetch_latest_review(args.pr, args.marker)
        if not body:
            print("NO_REVIEW", file=sys.stderr)
            return 1
        sys.stdout.write(body)
        return 0

    if args.cmd == "find-dispose":
        cid = t.find_disposed(args.pr, args.marker, args.fingerprint)
        if cid:
            print(cid)
        return 0

    if args.cmd == "post-dispose":
        body = open(args.body_file, encoding="utf-8").read()
        cid = t.post_dispose_comment(args.pr, body)
        print(f"posted comment_id={cid}")
        return 0

    if args.cmd == "file-issue":
        body = open(args.body_file, encoding="utf-8").read()
        url = t.file_batched_issue(
            title=args.title,
            body=body,
            pr=0,
            default_labels=args.label or ["themis-followup", "backlog"],
        )
        print(url)
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
