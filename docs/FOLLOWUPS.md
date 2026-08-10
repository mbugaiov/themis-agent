# Themis follow-ups (Suggestions / Risks / …)

Shared merge gate for all dual-review engines.

## Policy

| Section | Gate |
|---------|------|
| **Blocking issues** | CI fail until fixed in the PR |
| **Configured follow-up sections** (see below) | Must **fix in PR** or **file one batched** same-repo issue before merge |
| **Nits** (product / MVP repos) | **Comment-only** — do **not** gate merge; do **not** auto-file |

**Preferred:** fix every gated follow-up on the **same** source PR before merge (no filing).

**If deferring:** `file_review_followups.sh` opens **one** batched backlog issue with a checklist of all gated items. Factory pickup must close that checklist in **one** follow-up PR — never one issue/PR per bullet.

**Do not** file one GitHub issue per Risk/Nit bullet. That floods backlog with cosmetic debt.

Issues are always created on the **PR’s repository** (not a central Iris inbox).

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
| `scripts/check_review_followups_disposed.sh` | Fail if gated items lack disposal comment |
| `scripts/file_review_followups.sh` | File **one** batched backlog issue + post disposal marker |

## Engine wiring

1. Checkout this repo to `.themis-agent` (same as `ci_isolation.sh`).
2. Export engine-specific env, then call the scripts:

```bash
export THEMIS_REVIEW_MARKER='<!-- iris-agent-cursor-review -->'
export THEMIS_FOLLOWUP_DISPOSE_MARKER='<!-- iris-review-followups-disposed -->'
# Product example (preferred):
export THEMIS_FOLLOWUP_SECTIONS='Risks'
# Engine self-review example:
# export THEMIS_FOLLOWUP_SECTIONS='Suggestions,High priority issues,Risks'

bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
# or file:
bash .themis-agent/scripts/file_review_followups.sh <PR> --from-comment
```

3. Call the check at the end of `wait_*_pipeline` and in **auto-merge** (checkout **default branch** + `.themis-agent`, never PR head, before merge).

Thin wrappers under each engine’s `scripts/` should only set env and exec these scripts.
