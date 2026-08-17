---
name: themis-code-review
description: How to run Themis isolation as a sub-step of in-repo code review. Use when wiring or executing CR on engine/product PRs.
---

# Themis as CR sub-step

1. Run **in-repo** review per that repo’s `code-review.mdc` **and** the shared
   MUST-HAVE in `templates/engine-code-review-block.md` (new/changed behavior
   without new or updated tests → **Blocking**). CI prompts must cite both.
2. Run **`themis-isolation`** (mode engine or product).
3. Merge Isolation blockers into `## Blocking issues` (or fail a dedicated scan job).
4. `check_review_gate.sh review.md` must pass.

Do **not** delete or override project-specific Themis rules, and do **not**
weaken the shared tests MUST-HAVE. See `docs/WIRING.md`.
