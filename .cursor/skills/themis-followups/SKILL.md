---
name: themis-followups
description: >-
  Dispose gated Themis follow-ups before merge as fixed, accepted, or deferred.
  Prefer fix on the same PR; accepted caveats require rationale; deferred items use
  one batched same-repo backlog issue. Product repos gate Risks only (not Nits).
---

# Themis follow-ups

See [docs/FOLLOWUPS.md](../../../docs/FOLLOWUPS.md).

Triage every gated item:

- **fixed** (preferred) — addressed on the source PR; rationale names the commit or implementation.
- **accepted** — a documented caveat; rationale is mandatory and no issue is filed.
- **deferred** — only these items are sent to `file_review_followups.sh`, in **one** checklist issue that factory pickup closes in **one** PR.

Never accept security/authz/ACL/secrets, invented metrics or wrong buildId, data honesty, PII, or an OpenSpec `THEN` contradiction. Fix or defer those. Acceptable caveats include jsdom limits, class-token versus pixel checks, testid wording versus FR, and “`<external-stg-oracle>` remains oracle.”

**Product / MVP repos:** set `THEMIS_FOLLOWUP_SECTIONS=Risks` so **Nits stay comment-only** and do not flood backlog.

```bash
# After Themis green — triage.json covers every parsed item:
bash .themis-agent/scripts/dispose_review_followups.sh <PR> triage.json --from-comment
bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
```

Never merge with undisposed **gated** follow-ups. Never file into a different repo (e.g. Iris) for another engine’s PR. Never file one issue per nit.
