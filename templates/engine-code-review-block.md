# Shared MUST-HAVE — tests (moved)

**Canonical location:** [`../review-rules/10-tests-must-have.md`](../review-rules/10-tests-must-have.md)

Engines must load the full central pack via:

```bash
bash .themis-agent/scripts/build_review_prompt.sh --pr … --base … --label … \
  --local-rule .cursor/rules/code-review.mdc --themis-root .themis-agent
```

Do not copy this file into consumer repos. Add new shared rules only under
`review-rules/[0-9]*.md`.
