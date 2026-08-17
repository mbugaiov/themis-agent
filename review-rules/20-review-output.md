# 20 — Review output contract

Every Themis review comment / `review.md` must use these sections (exact headers):

- `## Summary`
- `## Blocking issues` — or `None.`
- `## Suggestions` — or `None.`
- `## High priority issues` — or `None.`
- `## Risks` — or `None.`

Or a single-line: `LGTM - no blocking issues found.` (only when Blocking would be
`None.` — never after listing real blockers).

## Gate

CI runs `check_review_gate.sh` on `review.md`. Non-empty **Blocking issues** fails
`review (Themis)`. Empty Blocking section (header with no `None.` / bullets) also fails.

## Isolation

Cross-tenant leaks / secrets / host paths are primarily the separate job
`isolation (Themis)`. Still fold obvious leak findings into Blocking here if seen.
