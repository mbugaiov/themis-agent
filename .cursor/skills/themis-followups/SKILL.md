---
name: themis-followups
description: >-
  Dispose Themis Suggestions/Risks before merge — prefer fix on the same PR;
  if deferring, file one batched same-repo backlog issue and fix together in one pickup PR.
---

# Themis follow-ups

See [docs/FOLLOWUPS.md](../../../docs/FOLLOWUPS.md).

**Preferred:** fix every follow-up on the source PR (sections `None.` / LGTM).

**If deferring:** `file_review_followups.sh` opens **one** checklist issue — factory pickup closes all items in **one** PR (never one issue/PR per bullet).

```bash
# After Themis green — either sections are None, or:
bash .themis-agent/scripts/file_review_followups.sh <PR> --from-comment
bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
```

Never merge with undisposed follow-ups. Never file into a different repo (e.g. Iris) for another engine’s PR.
