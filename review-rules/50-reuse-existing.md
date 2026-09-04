# 50 — MUST-CHECK: reuse existing code before adding parallel implementations

**Applies to every repo that runs `review (Themis)`.** Third substantive review
lens after tests (10) and change description (30): before approving a merge,
confirm the destination tree does not already expose the same capability.

Consumer `.cursor/rules/code-review.mdc` may tighten (e.g. page-object parent
reuse); it must **not** weaken this section.

Keep this file **tenant-agnostic** — no live product routes, class names, UI kits,
or customer id schemes. Use placeholders only.

## Why

PRs often re-implement page objects, API clients, helpers, fixtures, or whole
suites that already exist on the base branch (or differ only by naming / entry
navigation). That raises maintenance cost and drifts behavior. Reviewers must
**search the merge target**, not only read the diff.

Human reviewers should not have to restate “make it a shared fixture” after the
agent already saw the twin — that class of finding is **Blocking**, not a
Suggestion.

## Reviewer procedure (required)

1. Diff first: `git --no-pager diff origin/<base>...HEAD`.
2. From the diff, extract **symbols of intent**: new module/class names, route or
   API path prefixes, feature/case ids used by the project, markers, fixture
   names, and distinctive user-visible strings.
3. On **base** (destination), search for those intents — e.g. `git grep` /
   ripgrep over `origin/<base>` (or a worktree at base) for endpoints, paths,
   class/module names, fixtures, and near-synonyms of the feature under test.
4. Open any hits and decide: **extend / call / compose / parametrize** vs
   **new parallel**.

Do **not** stop at “diff looks clean.” Absence of conflict markers ≠ absence of
duplicates.

## Block on (put under `## Blocking issues`)

1. **Same surface already covered** — destination already has a page object,
   API module, or suite for the **same screen / endpoint / user flow**, and the
   PR adds a second parallel implementation instead of extending or calling it.
2. **Copy-paste twin** — new file or symbol is substantially the same as an
   existing module (same locators/endpoints/assertions with renames only) when a
   shared helper, subclass, or parametrized fixture would fit the repo’s patterns.
3. **Entry-only twin (page / fixture)** — new page object or pytest fixture
   duplicates an existing one for the **same screen / flow**, and the only
   material difference is how the test arrives there (tab, plant/site selector,
   sidebar entry, URL query, role). **Required fix:** one shared page object +
   parametrized (or composed) fixture / helper — not a second near-copy.
   Do **not** file this under Suggestions even if the comment would read as a
   “nice refactor.”
4. **Fixture / helper redefinition** — new fixture or helper duplicates an
   existing one under another name for the same scope without a documented
   isolation reason (different user, tenant, or lifecycle). Prefer extend /
   parametrize / import the existing fixture.
5. **Bypass of an existing client** — tests/call sites use raw HTTP / ad-hoc
   requests while a project API module (or equivalent) already wraps that
   endpoint.

Cite `path:line` on **both** the new code and the existing reusable path.

**Not a Suggestion / not High-only:** “largely duplicates `<existing_fixture>` /
`<ExistingPage>`; navigation differs only by tab/plant/entry — share a
parametrized fixture.” That is **Blocking** (entry-only twin). Filing a backlog
issue and merging is **not** disposal for this class.

## High priority (withhold approval; may be non-pipeline-blocking per consumer)

1. **Near-duplicate widgets** — shared UI control patterns (date range, table
   loading, search field, dropdown) copied wholesale from another page when the
   repo already has a shared base/mixin **or** the PR could trivially call an
   existing method — but the pages are still **different screens** (not an
   entry-only twin of the same flow; those are Blocking above).

## Suggestions only (do not block)

- Extracting a **new** shared mixin/base when none exists yet and the PR only
  introduces the **first** page of a family (note follow-up extract — do not
  invent a second page twin in the same PR).
- Intentional second implementation with an explicit ADR / PR description
  (“replace X”, “old path deprecated”).
- Purely coincidental naming with different domains / different user flows.

## What “enough reuse check” looks like in the review

In `## Summary` or a Blocking/High bullet, briefly state what was searched on
base (e.g. “grepped `<api-path>`, `<Feature>Page`, `<fixture_name>`, `<case-id>`
on origin/main — prior suite/fixture hit → Blocking twin; no prior suite;
similar control patterns on another screen only → High / Suggestion”).

If the check was skipped, say so under **High priority** — silent skip is not OK
for PRs that add new modules under common app trees (`pages/`, `api*`, `lib/`,
`scripts/`, `tests/`, `fixtures/`, or the consumer’s equivalent).
