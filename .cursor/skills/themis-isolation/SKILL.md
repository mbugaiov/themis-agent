---
name: themis-isolation
description: Isolation / portability / cross-tenant / short security review of docs, skills, rules, templates — not language style. Use as CR sub-step on engine and product PRs.
---

# Themis isolation review

## Modes

### `engine` (dev-agent, qa-agent, ux-agent, themis-agent, …)

Block in **tracked** engine files (diff + nearby context):

- Live product/project **slugs**, epic keys, board IDs
- Absolute host paths (`/Users/…`), private STG/IPs
- Customer brand names that belong in a single tenant project
- Secrets: tokens, `api_key=`, webhook URLs with secrets, `.env` bodies
- Copy-paste of another engine’s project-specific runbook into shared skills
- Inconsistent skill/rule contracts that break the portable factory model

Allow: placeholders (`<slug>`, `RQ-####` examples clearly fictional like `TST-*`),
`projects/_template/`.

### `product` (app repos)

Allow: this product’s name, epic, STG, domain.

Block:

- **Other customers’** slugs, epics, STG hosts, brand copy
- Secrets and credentials in the diff
- Engine-only internals that embed a *different* tenant’s factory paths
- Shipping another product’s `DESIGN.md` / OpenSpec slices by mistake

## Process

1. `git --no-pager diff origin/<base>...HEAD` (or provided range).
2. Prefer `bash scripts/isolation_scan.sh --mode <engine|product> --root <repo>`.
3. Manually read changed `*.md`, `SKILL.md`, `.mdc`, workflow YAML prompts.
4. Emit findings for the parent CR to fold into `## Blocking issues`.

## Output (for parent review.md)

Prefer folding into the parent gate:

```markdown
## Blocking issues
- `path:line` — isolation: …
```

Or intermediate:

```markdown
## Isolation (Themis)
None.
```

## Short security (always)

- No secrets in markdown/skills/workflows
- No widening of hook permissions without justification
- No `CURSOR_API_KEY` or tokens committed
