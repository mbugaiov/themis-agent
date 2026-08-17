# 30 — Change description must be present

## Block on (or elevate to Blocking when intent is opaque)

1. **No meaningful PR description** and no clear `## Summary` of *why* the change
   exists (empty body, “fix”, “wip”, or title-only with no intent) when the diff
   is non-trivial — Blocking.
2. **Summary that only lists files** without stating behavior/contract impact —
   treat as incomplete; Blocking for behavior-changing PRs.
3. **Missing link to tracker / issue** when the repo normally requires one and the
   change is a product/engine feature — Suggestions unless local `code-review.mdc`
   marks it Blocking.

## What “good” looks like

- One or two sentences: problem → approach → how tested.
- Call out risk / migration / follow-ups explicitly when relevant.
- For shared-rule PRs on this engine: name which `review-rules/NN-*.md` files were
  added or changed.
