# Themis follow-ups (Suggestions / Risks / …)

Shared merge gate for all dual-review engines.

## Policy

| Section | Gate |
|---------|------|
| **Blocking issues** | CI fail until fixed in the PR |
| **Configured follow-up sections** (see below) | Must dispose each item as **fixed**, **accepted**, or **deferred** before merge |
| **Nits** (product / MVP repos) | **Comment-only** — do **not** gate merge; do **not** auto-file |

**Preferred:** mark every gated follow-up **fixed** on the **same** source PR, with the commit or implementation detail in its rationale.

**Accepted caveat:** use **accepted** only for a real limitation or oracle caveat and provide a rationale. Typical acceptable cases are jsdom limits, class-token assertions instead of pixel checks, testid wording versus a functional requirement, and “Argus STG remains oracle.” Acceptance never files an issue.

Acceptance is forbidden for security/authz/ACL/secrets, invented metrics or a wrong buildId, data honesty, PII, and OpenSpec `THEN` contradictions. These must be fixed or deferred.

**If deferring:** only **deferred** items go through `file_review_followups.sh`, which opens **one** batched backlog issue with a checklist. Factory pickup must close that checklist in **one** follow-up PR — never one issue/PR per bullet.

**Do not** file one GitHub issue per Risk/Nit bullet. That floods backlog with cosmetic debt.

### Tracker + SCM matrix

| Product style | `THEMIS_FOLLOWUP_SCM` | `THEMIS_FOLLOWUP_TRACKER` | Where review/dispose lives | Where batched issue is filed |
|---------------|----------------------|---------------------------|----------------------------|------------------------------|
| **GitHub engines** (default) | `github` (default) | `github` (default) | GitHub PR comments | GitHub Issues on PR repo |
| **Bitbucket + Jira** (e.g. SolArk) | `bitbucket` | `jira` | Bitbucket PR comments | **One** Jira Task under product epic |

GitHub path is unchanged when env vars are unset.

### Recommended `THEMIS_FOLLOWUP_SECTIONS`

| Repo type | Sections | Why |
|-----------|----------|-----|
| **Product / MVP** | `Risks` only | Nits are polish noise; keep backlog for correctness/security |
| **Engine self-review** | `Suggestions,High priority issues,Risks` | Engines may still track Suggestions |
| Legacy / explicit polish pass | `Risks,Nits` | Only when intentionally farming nits |

## Scripts (this repo)

| Script | Role |
|--------|------|
| `scripts/review_followups.py` | Parse follow-up sections + fingerprint |
| `scripts/followups_transport.py` | SCM/tracker adapter (GitHub, Bitbucket, Jira) |
| `scripts/check_review_followups_disposed.sh` | Fail if gated items lack disposal comment |
| `scripts/file_review_followups.sh` | File **one** batched backlog issue + post disposal marker |
| `scripts/dispose_review_followups.py` | Validate triage and build structured disposal artifacts |
| `scripts/dispose_review_followups.sh` | Dispose items as fixed / accepted / deferred |

## Environment

### Shared

```bash
export THEMIS_REVIEW_MARKER='<!-- iris-agent-cursor-review -->'
export THEMIS_FOLLOWUP_DISPOSE_MARKER='<!-- iris-review-followups-disposed -->'
export THEMIS_FOLLOWUP_SECTIONS='Risks'   # product example
```

### Transport (defaults = GitHub)

| Variable | Values | Purpose |
|----------|--------|---------|
| `THEMIS_FOLLOWUP_SCM` | `github` \| `bitbucket` | Where to read/post PR comments |
| `THEMIS_FOLLOWUP_TRACKER` | `github` \| `jira` | Where to file batched backlog issue |

### Bitbucket SCM

```bash
export THEMIS_FOLLOWUP_SCM=bitbucket
export BITBUCKET_WORKSPACE=sol-ark
export BITBUCKET_REPO_SLUG=ai-support-agent
# or: export THEMIS_FOLLOWUP_BB_REPO=sol-ark/ai-support-agent
export BITBUCKET_USERNAME=you@company.com
export BITBUCKET_TOKEN=...          # or BITBUCKET_APP_PASSWORD
```

### Jira tracker

```bash
export THEMIS_FOLLOWUP_TRACKER=jira
export JIRA_BASE_URL=https://your-co.atlassian.net
export JIRA_EMAIL=you@company.com
export JIRA_API_TOKEN=...
export JIRA_PROJECT_KEY=RQ
export THEMIS_FOLLOWUP_JIRA_EPIC=RQ-2000
# optional extra labels (comma-separated):
# export THEMIS_FOLLOWUP_JIRA_LABELS=solark
```

Jira issues get labels `themis-followup` + `impl-dev` (+ extras). Source PR URL in the body points at the Bitbucket PR when `THEMIS_FOLLOWUP_SCM=bitbucket`.

## Engine wiring

1. Checkout this repo to `.themis-agent` (same as `ci_isolation.sh`).
2. Export engine-specific env, then call the scripts:

```bash
# GitHub product (default):
bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
bash .themis-agent/scripts/dispose_review_followups.sh <PR> triage.json --from-comment

# Bitbucket + Jira product:
export THEMIS_FOLLOWUP_SCM=bitbucket
export THEMIS_FOLLOWUP_TRACKER=jira
# … Bitbucket + Jira creds …
bash .themis-agent/scripts/check_review_followups_disposed.sh <PR_ID>
bash .themis-agent/scripts/dispose_review_followups.sh <PR_ID> triage.json --from-comment
```

`triage.json` addresses every parsed review item by its one-based order:

```json
[
  {"item": 1, "disposition": "fixed", "rationale": "commit abc123 adds the guard"},
  {"item": 2, "disposition": "accepted", "rationale": "jsdom cannot measure layout; Argus STG remains oracle"},
  {"item": 3, "disposition": "deferred", "rationale": "requires the planned migration"}
]
```

Fixed and accepted items require rationale. Missing items, duplicate items, unsafe acceptance, or accepted-without-rationale fail before any issue or disposal comment is posted.

3. Call the check at the end of `wait_*_pipeline` and in **auto-merge** (checkout **default branch** + `.themis-agent`, never PR head, before merge).

4. **Bitbucket Pipeline** (after Themis review step): run `check_review_followups_disposed.sh`; on failure optionally `file_review_followups.sh --from-comment` before merge gate.

Thin wrappers under each engine’s `scripts/` should only set env and exec these scripts.

## Idempotency

If a dispose comment with the same review **fingerprint** already exists on the PR/MR, either disposal path exits without re-filing. Historical short-form disposal comments remain valid because `check_review_followups_disposed.sh` still gates only on the unchanged marker + fingerprint contract.
