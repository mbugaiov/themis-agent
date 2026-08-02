# Wiring Isolation sub-step into existing CR

Keep each repo’s `code-review.mdc` for **project-specific** review. Add Themis isolation
as an **additional** obligation in the same `review.md` (or a second artifact).

## 1. Engine repos (`dev-agent`, `qa-agent`, `ux-agent`, `themis-agent`)

In `.cursor/rules/code-review.mdc`, require a section:

```markdown
## Isolation (Themis)
None.
```

Or list blockers. Prompt the reviewer to also follow skill `themis-isolation` (mode=`engine`)
when `themis-agent` is on the workspace / `THEMIS_AGENT_PATH` is set.

Deterministic preflight (optional in `pre_merge_check.sh`):

```bash
bash "$THEMIS_AGENT_PATH/scripts/isolation_scan.sh" --mode engine --root "$PWD"
# or: bash scripts/isolation_scan.sh --mode engine   # if script vendored/copied
```

`check_review_gate.sh` continues to parse `## Blocking issues`. Isolation findings may be
listed under `## Blocking issues` **or** under `## Isolation (Themis)` — if you use the
latter, either fold into Blocking issues before the gate, or extend the gate (preferred:
fold into Blocking issues).

## 2. Product repos

Mode=`product`. Pass known peer tenants to the scanner:

```bash
bash isolation_scan.sh --mode product --root "$PWD" \
  --peer-pattern 'other-customer|other-slug|FOREIGN-EPIC'
```

Allow this product’s slug/epic in docs; block peers and secrets.

## 3. Cursor Task sub-step (optional)

After in-repo Themis draft `review.md`, spawn Task: “Run themis-isolation on
`git diff origin/<base>...HEAD`; append Isolation blockers into review.md.”
