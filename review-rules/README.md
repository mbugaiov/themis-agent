# Shared Themis review rules (central pack)

These files are the **portable code-review brain** for every repo that runs
`review (Themis)`.

## How it works

1. Consumer CI checkouts `themis-agent` → `.themis-agent/` (prefer **unpinned `main`**
   for this pack so new rules apply on the next review without editing engines).
2. Workflow runs `bash .themis-agent/scripts/build_review_prompt.sh …`.
3. That script **inlines every** `review-rules/[0-9]*.md` (sorted) into the prompt.
4. Local `.cursor/rules/code-review.mdc` is appended as product/engine-specific
   extras — it must **not** weaken shared rules.

## Add a new central rule

1. Add `review-rules/NN-short-name.md` (two-digit prefix for order).
2. Open a PR on **themis-agent**; merge to `main`.
3. Done — next `review (Themis)` on any wired repo loads it automatically.
   No copy-paste into consumer `code-review.mdc` files.

Do **not** put sibling product brand names or customer slugs in these files
(isolation will block). Keep wording portable.

## Pack order (substantive lenses)

| File | Lens |
|------|------|
| `10-tests-must-have` | Behavior change ⇒ tests in same PR |
| `20-review-output` | Required `review.md` sections / gate |
| `30-change-description` | Opaque / missing intent |
| `40-wiring-review-float` | Do not Blocking-flag unpinned review checkout |
| `50-reuse-existing` | Search **base** for duplicate / near-duplicate code to reuse — **entry-only page/fixture twins are Blocking** |

## Local vs shared

| Layer | Where |
|-------|--------|
| Shared must-haves (tests, output, description, reuse, …) | **This directory** |
| Engine/product DoD, domain blockers | Consumer `code-review.mdc` |
| Cross-tenant / secrets / host paths | `isolation (Themis)` job |
