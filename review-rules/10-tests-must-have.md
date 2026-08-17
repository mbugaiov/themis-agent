# 10 — MUST-HAVE: tests with every behavior change

**Applies to every repo that runs `review (Themis)`.** Consumer
`.cursor/rules/code-review.mdc` may add product-specific blockers; it must
**not** weaken this section.

## Block on (put under `## Blocking issues`)

When the PR diff introduces or changes **runtime / contract behavior**
(scripts, libs, skills that affect decisions, workflows, CLI, factory ticks,
handoffs, probes, gates, parsers, APIs):

1. **No new tests** for the new path — Blocking.
2. **Existing tests not updated** when behavior/contracts changed — Blocking.
3. **Docs/rules/skills-only claims of coverage** (`test -f` / `grep` smoke
   without asserting the decision) when the change is decision logic — Blocking
   unless a real unit/contract assertion is also present.
4. **“Tests later” / follow-up issue instead of tests in this PR** — Blocking
   for behavior changes (file follow-ups only for non-blocking Suggestions).

### What counts as enough

| Change type | Minimum bar |
|-------------|-------------|
| Pure decision / parse / classify / gate | Unit/contract test under `tests/` (vitest/node/bash assert) run by `tests/run_tests.sh` or `npm test` |
| Shell wiring that calls a pure lib | Test the lib + smoke that wiring invokes it |
| Product / app feature path | Project automation or TC + regression path in that product’s QA/dev factory |
| Pure docs / comments / typos | No new tests required |

### Reviewer instructions

- Diff first: `git --no-pager diff origin/<base>...HEAD`.
- If behavior changed and the diff has **zero** test file changes → Blocking
  unless the change is explicitly non-behavioral.
- If behavior changed and tests exist but do not cover the new branch /
  negative path → Blocking (name the missing case).
- Prefer concrete Blocking bullets: file path + what assertion is missing.
