# Wiring: review floats, isolation may pin

Documented contract (`docs/WIRING.md`, `review-rules/README.md`):

- **`review (Themis)`** checkouts `themis-agent` **unpinned** (`main`) so new
  `review-rules/NN-*.md` apply without a consumer PR.
- **`isolation (Themis)`** / `ensure_themis_agent.sh` / local preflight **may** pin a
  SHA for script stability.

## Do not mark Blocking

- Review job without `ref:` while isolation/ensure pin a SHA — intentional, not drift.
- Asking consumers to pin the review-rules pack checkout — that breaks auto-apply.

## Do mark Blocking

- Review job that **hardcodes** individual `review-rules/NN-*.md` paths instead of
  `build_review_prompt.sh`.
- Review job missing the builder / pack checkout entirely.
