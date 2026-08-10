---
name: themis-followups
description: >-
  Dispose gated Themis follow-ups before merge — prefer fix on the same PR;
  if deferring, file one batched same-repo backlog issue and fix together in one pickup PR.
  Product repos gate Risks only (not Nits).
---

# Themis follow-ups

See [docs/FOLLOWUPS.md](../../../docs/FOLLOWUPS.md).

**Preferred:** fix gated follow-ups on the source PR (sections `None.` / LGTM).

**If deferring:** `file_review_followups.sh` opens **one** checklist issue — factory pickup closes all items in **one** PR (never one issue/PR per bullet).

**Product / MVP repos:** set `THEMIS_FOLLOWUP_SECTIONS=Risks` so **Nits stay comment-only** and do not flood backlog.

```bash
# After Themis green — either gated sections are empty, or:
bash .themis-agent/scripts/file_review_followups.sh <PR> --from-comment
bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
```

Never merge with undisposed **gated** follow-ups. Never file into a different repo (e.g. Iris) for another engine’s PR. Never file one issue per nit.
