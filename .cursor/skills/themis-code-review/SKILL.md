---
name: themis-code-review
description: How to run Themis isolation as a sub-step of in-repo code review. Use when wiring or executing CR on engine/product PRs.
---

# Themis as CR sub-step

1. Run **centralized** review: `scripts/build_review_prompt.sh` inlines every
   `review-rules/[0-9]*.md`, then local `code-review.mdc` (must not weaken the pack).
2. Run **`themis-isolation`** (mode engine or product).
3. Merge Isolation blockers into `## Blocking issues` (or fail a dedicated scan job).
4. `check_review_gate.sh review.md` must pass.

Do **not** delete or override project-specific local CR rules, and do **not**
weaken the shared tests MUST-HAVE. See `docs/WIRING.md` and `review-rules/README.md`.
