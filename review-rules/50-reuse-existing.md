# 50 — MUST-CHECK: reuse existing code before adding parallel implementations

**Applies to every repo that runs `review (Themis)`.** Third substantive review
lens after tests (10) and change description (30): before approving a merge,
confirm the destination tree does not already expose the same capability.

Consumer `.cursor/rules/code-review.mdc` may tighten (e.g. POM parent reuse);
it must **not** weaken this section.

## Why

PRs often re-implement page objects, API clients, helpers, or whole suites that
already exist on the base branch (or differ only by naming). That raises
maintenance cost and drifts behavior. Reviewers must **search the merge target**,
not only read the diff.

## Reviewer procedure (required)

1. Diff first: `git --no-pager diff origin/<base>...HEAD`.
2. From the diff, extract **symbols of intent**: new page/API class names, route
   prefixes (`/log/uphold`, `api/v1/logger`), feature labels (TestRail / MSA ids),
   markers, fixture names, and distinctive UI strings.
3. On **base** (destination), search for those intents — e.g. `git grep` /
   ripgrep over `origin/<base>` (or a worktree at base) for endpoints, page
   paths, class/module names, and near-synonyms (`maintenance` / `uphold` /
   `logger`, etc.).
4. Open any hits and decide: **extend / call / compose** vs **new parallel**.

Do **not** stop at “diff looks clean.” Absence of conflict markers ≠ absence of
duplicates.

## Block on (put under `## Blocking issues`)

1. **Same surface already covered** — destination already has a page object,
   API module, or suite for the **same screen / endpoint / user flow**, and the
   PR adds a second parallel implementation instead of extending or calling it.
2. **Copy-paste twin** — new file is substantially the same as an existing
   module (same locators/endpoints/assertions with renames only) when a shared
   helper or subclass would fit the repo’s patterns.
3. **Bypass of an existing client** — tests/call sites use raw HTTP / ad-hoc
   requests while a project API module (or equivalent) already wraps that
   endpoint.

Cite `path:line` on **both** the new code and the existing reusable path.

## High priority (withhold approval; may be non-pipeline-blocking per consumer)

1. **Near-duplicate widgets** — date range, table spinner, SN search, dropdown
   patterns copied wholesale from another page when the repo already has a
   shared base/mixin **or** the PR could trivially call an existing method.
2. **Fixture / helper redefinition** — new fixture duplicates an existing one
   under another name without a clear scope reason.

## Suggestions only (do not block)

- Parallel POMs that mirror Element UI patterns **when the repo convention is
  per-page locators** and no shared mixin exists yet (note as follow-up extract).
- Intentional second implementation with an explicit ADR / PR description
  (“replace X”, “old path deprecated”).
- Purely coincidental naming with different domains.

## What “enough reuse check” looks like in the review

In `## Summary` or a Blocking/High bullet, briefly state what was searched on
base (e.g. “grepped `api/v1/logger`, `MaintenanceLog`, `uphold` on origin/main —
no prior suite; EventPage timeline is pattern-similar only → Suggestion”).

If the check was skipped, say so under **High priority** — silent skip is not OK
for PRs that add new modules under `pages/`, `api*`, `lib/`, `scripts/`, or
`tests/`.
