# Themis (central review + isolation engine)

**Themis** owns:

1. **Centralized PR code-review rules** (`review-rules/`) applied by every
   `review (Themis)` job via `scripts/build_review_prompt.sh`.
2. **Isolation / consistency** scanners (`themis-isolation`, `ci_isolation.sh`).

| Layer | Owner |
|-------|--------|
| Shared must-haves (tests, output contract, description, …) | **This repo** `review-rules/` |
| Language, architecture, product DoD extras | Consumer `code-review.mdc` (must not weaken shared pack) |
| Customer/project leaks, secrets, engine consistency | **This engine** (`themis-isolation`) |

Add a shared rule once → merge to `main` → next review on every wired repo loads it
(no per-engine copy-paste). See `docs/WIRING.md` and `review-rules/README.md`.

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
