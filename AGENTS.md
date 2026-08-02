# Themis — isolation & consistency engine (`themis-agent`)

**Themis** (brand) here means the **portable review brain** for isolation, portability,
short security hygiene, and cross-engine consistency. Product language/architecture CR
stays in each repo’s own `.cursor/rules/code-review.mdc`.

> Pantheon: Themis · Review. `engineHome` = this repo. In-app CR workflows remain the
> primary gate; this engine supplies the **Isolation sub-step** + scanners.

## Skills

| When | Skill |
|------|--------|
| Isolation / portability / cross-tenant / secrets on a diff | `themis-isolation` |
| How to run as CR sub-step + output format | `themis-code-review` |

## Hard rules

- **Not a language linter** — do not focus on TypeScript/Python style.
- **Docs, skills, rules, templates, workflow prompts** are first-class.
- **Engines** = multi-tenant brain → maximum sterility.
- **Products** = tenant home → project words OK; **customer B must not appear in customer A**.
- Ship engine changes via **GitHub PR** on this repo.
- Never replace project-specific Themis rules — only add the Isolation sub-step.

## Layout

```
themis-agent/
  AGENTS.md  README.md  PORTABILITY.md  docs/WIRING.md
  .cursor/skills/  .cursor/rules/
  scripts/isolation_scan.sh
  templates/
```
