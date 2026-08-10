# Themis follow-ups (Suggestions / Risks / …)

Shared merge gate for all dual-review engines.

## Policy

| Section | Gate |
|---------|------|
| **Blocking issues** | CI fail until fixed in the PR |
| **Suggestions / High priority / Risks / Nits** (configurable) | Must **fix in PR** or **file same-repo** GitHub issues before merge |

**Preferred:** fix every follow-up on the **same** source PR before merge (no filing).

**If deferring:** `file_review_followups.sh` opens **one** batched backlog issue with a checklist of all items. Factory pickup must close that checklist in **one** follow-up PR — never one issue/PR per bullet.

Issues are always created on the **PR’s repository** (not a central Iris inbox).

## Scripts (this repo)

| Script | Role |
|--------|------|
| `scripts/review_followups.py` | Parse follow-up sections + fingerprint |
| `scripts/check_review_followups_disposed.sh` | Fail if open items lack disposal comment |
| `scripts/file_review_followups.sh` | File issues + post disposal marker |

## Engine wiring

1. Checkout this repo to `.themis-agent` (same as `ci_isolation.sh`).
2. Export engine-specific env, then call the scripts:

```bash
export THEMIS_REVIEW_MARKER='<!-- iris-agent-cursor-review -->'
export THEMIS_FOLLOWUP_DISPOSE_MARKER='<!-- iris-review-followups-disposed -->'
export THEMIS_FOLLOWUP_SECTIONS='Suggestions,High priority issues,Risks'
# pantheon example:
# export THEMIS_FOLLOWUP_SECTIONS='Risks,Nits'
# export THEMIS_REVIEW_MARKER='<!-- pantheon-themis-review -->'

bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
# or file:
bash .themis-agent/scripts/file_review_followups.sh <PR> --from-comment
```

3. Call the check at the end of `wait_*_pipeline` and in **auto-merge** (checkout **default branch** + `.themis-agent`, never PR head, before merge).

Thin wrappers under each engine’s `scripts/` should only set env and exec these scripts.
