# Themis — isolation & consistency engine (`themis-agent`)

**Themis** (brand) here means the **portable review brain**:
1. **Central code-review rules** — `review-rules/[0-9]*.md`, loaded by every
   `review (Themis)` job via `scripts/build_review_prompt.sh` (add a rule once
   here → applies on the next review everywhere without editing engines).
2. **Isolation / portability / secrets** — `themis-isolation` + `ci_isolation.sh`.

Product language/architecture extras stay in each repo’s `.cursor/rules/code-review.mdc`
(must not weaken the shared pack).

> Pantheon: Themis · Review. `engineHome` = this repo.

## Skills

| When | Skill |
|------|--------|
| Isolation / portability / cross-tenant / secrets on a diff | `themis-isolation` |
| How to run as CR sub-step + output format | `themis-code-review` |

## Hard rules

- **Not a language linter** — do not focus on TypeScript/Python style.
- **Shared review policy lives in `review-rules/`** — never copy into consumers.
- **Docs, skills, rules, templates, workflow prompts** are first-class.
- **Engines** = multi-tenant brain → maximum sterility.
- **Products** = tenant home → project words OK; **customer B must not appear in customer A**.
- Ship engine changes via **GitHub PR** on this repo.
- Never replace project-specific local CR rules — only add shared pack + Isolation.

## Layout

```
themis-agent/
  AGENTS.md  README.md  PORTABILITY.md  docs/WIRING.md
  review-rules/          # central CR pack (auto-inlined into all reviews)
  scripts/build_review_prompt.sh
  scripts/isolation_scan.sh
  .cursor/skills/  .cursor/rules/
  templates/
```
