---
name: themis-followups
description: Dispose Themis Suggestions/Risks before merge — fix in PR or file same-repo backlog.
---

# Themis follow-ups

See [docs/FOLLOWUPS.md](../../../docs/FOLLOWUPS.md).

```bash
# After Themis green — either sections are None, or:
bash .themis-agent/scripts/file_review_followups.sh <PR> --from-comment
bash .themis-agent/scripts/check_review_followups_disposed.sh <PR>
```

Never merge with undisposed follow-ups. Never file into a different repo (e.g. Iris) for another engine’s PR.
