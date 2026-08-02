# Themis (isolation engine)

**Themis** already lives in each **app repo** as project-specific PR code review.
This repository is the **portable isolation / consistency engine** — a mandatory
**sub-step** for engine PRs and an optional cross-tenant pass for product PRs.

| Layer | Owner |
|-------|--------|
| Language, architecture, product DoD | **In-repo Themis** (app / engine `code-review.mdc`) |
| Customer/project leaks, secrets, engine consistency | **This engine** (`themis-isolation`) |

## Modes

- **`engine`** — tracked files must not contain live customer/project slugs, epic keys,
  host paths, STG URLs, or secrets. Skills/rules/docs stay portable.
- **`product`** — this tenant’s names are OK; **other** tenants’ identifiers, shared
  secrets, and cross-customer copy-paste are blockers.

## Quickstart

```bash
git clone git@github.com:mbugaiov/themis-agent.git
cd themis-agent
bash scripts/isolation_scan.sh --mode engine --root /path/to/dev-agent
```

Wire into existing CR: see `docs/WIRING.md`. Skills: `themis-isolation`, `themis-code-review`.
