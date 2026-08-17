#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ✓ $1"; }
no(){ FAIL=$((FAIL+1)); echo "  ✗ $1"; }
have(){ [[ -e "$1" ]] && ok "exists: $1" || no "missing: $1"; }

echo "== scaffold =="
for f in AGENTS.md README.md PORTABILITY.md docs/WIRING.md \
  .cursor/skills/themis-isolation/SKILL.md \
  .cursor/skills/themis-code-review/SKILL.md \
  .cursor/rules/themis-engine.mdc \
  scripts/isolation_scan.sh; do
  have "$f"
done
chmod +x scripts/isolation_scan.sh

echo "== review gate =="
have "scripts/review_gate.py"
have "scripts/check_review_gate.sh"
BANNER_LGTM=$(mktemp)
cat > "$BANNER_LGTM" <<'EOF'
### Themis started
**Ticket:** engine
**Mode:** engine
**Doing:** isolation

LGTM - no blocking issues found.
EOF
bash scripts/check_review_gate.sh "$BANNER_LGTM" >/dev/null \
  && ok "review gate allows seat-started preamble before LGTM" \
  || no "review gate must pass LGTM after ### Seat started banner"
rm -f "$BANNER_LGTM"
EMPTY_BLOCK=$(mktemp)
cat > "$EMPTY_BLOCK" <<'EOF'
## Summary
x
## Blocking issues

## Suggestions
y
EOF
bash scripts/check_review_gate.sh "$EMPTY_BLOCK" >/dev/null \
  && no "empty Blocking section must fail" \
  || ok "empty Blocking section fails gate"
EMPTY_ERR=$(bash scripts/check_review_gate.sh "$EMPTY_BLOCK" 2>&1 >/dev/null || true)
[[ "$EMPTY_ERR" == *"incomplete / empty Blocking section"* ]] \
  && ok "empty Blocking stderr names incomplete section" \
  || no "empty Blocking stderr should say incomplete / empty Blocking section"
rm -f "$EMPTY_BLOCK"
# LGTM after a real Blocking body (intervening ##) must not override blockers.
LGTM_AFTER=$(mktemp)
cat > "$LGTM_AFTER" <<'EOF'
## Summary
Looks fine overall.

## Blocking issues
1. Secrets leaked in tracked file.

## Suggestions
None.

LGTM - no blocking issues found.
EOF
bash scripts/check_review_gate.sh "$LGTM_AFTER" >/dev/null \
  && no "LGTM must not override non-empty Blocking" \
  || ok "LGTM after blockers still fails gate"
rm -f "$LGTM_AFTER"

echo "== scan self (engine) =="
if bash scripts/isolation_scan.sh --mode engine --root "$ROOT"; then
  ok "self scan clean"
else
  no "self scan should be clean"
fi

echo "== isolation pathspec exclude (not line-grep) =="
ISO_TMP=$(mktemp -d)
cleanup_iso() { rm -rf "$ISO_TMP"; }
trap cleanup_iso EXIT
# Build leak fixtures at runtime so this test file does not self-match isolation_scan.
FAKE_GHP="ghp_""abcdefghijklmnopqrstuvwxyz12"
FAKE_HOST="/Users/""ci/Downloads/secret-data"
FAKE_AT="ATA""TT3"
(
  cd "$ISO_TMP"
  git init -q
  git config user.email "test@example.com"
  git config user.name "test"
  echo base > README
  git add README && git commit -qm base
  # (1) Secret outside the scanner must still flag.
  printf 'token=%s\n' "$FAKE_GHP" > app.env
  # (2) Line mentions isolation_scan.sh *and* a host path — must NOT be dropped.
  printf 'note scripts/isolation_scan.sh path=%s\n' "$FAKE_HOST" > notes.txt
  git add app.env notes.txt && git commit -qm leaks
)
ISO_OUT=$(bash scripts/isolation_scan.sh --mode engine --root "$ISO_TMP" --base HEAD~1 2>&1 || true)
[[ "$ISO_OUT" == *'isolation (secrets):'* ]] \
  && [[ "$ISO_OUT" == *'isolation (host-paths):'* ]] \
  && [[ "$ISO_OUT" == *Downloads* || "$ISO_OUT" == *notes.txt* ]] \
  && ok "isolation --base flags secret+hostpath (keeps isolation_scan.sh mention lines)" \
  || no "isolation --base pathspec exclude regression"
# Scanner-only SECRET= edit must stay excluded (pathspec), not via line filter.
(
  cd "$ISO_TMP"
  git checkout -q -b scanner-only
  mkdir -p scripts
  # Minimal stand-in; real exclude is by path name.
  printf "SECRET='(%s|%s)'\n" "$FAKE_AT" "$FAKE_GHP" > scripts/isolation_scan.sh
  git add scripts/isolation_scan.sh && git commit -qm 'scanner literals only'
)
if bash scripts/isolation_scan.sh --mode engine --root "$ISO_TMP" --base HEAD~1 >/dev/null 2>&1; then
  ok "isolation excludes scripts/isolation_scan.sh via pathspec"
else
  no "isolation should not flag scanner-only SECRET= path"
fi
rm -rf "$ISO_TMP"
trap - EXIT

echo "== follow-ups =="
# Ignore caller/product engine env so defaults match fixtures / fingerprints.
unset THEMIS_FOLLOWUP_SECTIONS THEMIS_REVIEW_MARKER THEMIS_FOLLOWUP_DISPOSE_MARKER
for f in scripts/review_followups.py scripts/check_review_followups_disposed.sh \
  scripts/file_review_followups.sh docs/FOLLOWUPS.md; do
  have "$f"
done
chmod +x scripts/check_review_followups_disposed.sh scripts/file_review_followups.sh scripts/review_followups.py
FU_NONE=$(python3 scripts/review_followups.py tests/fixtures/review-followups/none.md --json)
echo "$FU_NONE" | grep -q '"count": 0' && ok "followups none" || no "followups none"
FU_LGTM=$(python3 scripts/review_followups.py tests/fixtures/review-followups/none-with-lgtm.md --json)
echo "$FU_LGTM" | grep -q '"count": 0' && ok "followups none-with-lgtm" || no "followups none-with-lgtm"
FU_MIX=$(python3 scripts/review_followups.py tests/fixtures/review-followups/mixed.md --json)
echo "$FU_MIX" | grep -q '"count": 4' && ok "followups mixed count=4" || no "followups mixed"
MIX_FP=$(echo "$FU_MIX" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])')
[[ "$MIX_FP" == "c0b1fd20198917df" ]] && ok "followups mixed fingerprint" || no "followups fingerprint drift ($MIX_FP)"
FU_RN=$(THEMIS_FOLLOWUP_SECTIONS='Risks,Nits' python3 scripts/review_followups.py tests/fixtures/review-followups/risks-nits.md --json)
echo "$FU_RN" | grep -q '"count": 2' && ok "followups Risks+Nits" || no "followups Risks+Nits"
grep -q 'ONE batched follow-up issue' scripts/file_review_followups.sh \
  && grep -q 'fix together in one PR' scripts/file_review_followups.sh \
  && grep -q '1 item' scripts/file_review_followups.sh \
  && ok "followups file as one batched issue" \
  || no "followups batch filing policy missing from file_review_followups.sh"
# Unit-check generated issue body (no gh) — one checklist issue for all items.
# Use [[ ]] not echo|grep -q: with bash -e + pipefail, grep -q closes early → SIGPIPE.
BODY_MIX=$(python3 scripts/review_followups.py tests/fixtures/review-followups/mixed.md \
  --issue-body --pr 42 --repo owner/demo)
CHECK_N=$(printf '%s\n' "$BODY_MIX" | grep -cE '^- \[ \] \*\*' || true)
[[ "$BODY_MIX" == *'Fix **all** checklist items in **one** follow-up PR'* ]] \
  && [[ "$BODY_MIX" == *'do not open one PR per bullet'* ]] \
  && [[ "$BODY_MIX" == *'### Checklist'* ]] \
  && [[ "$BODY_MIX" == *'**Items:** 4'* ]] \
  && [[ "$BODY_MIX" == *"**Fingerprint:** \`$MIX_FP\`"* ]] \
  && [[ "$BODY_MIX" == *'file_review_followups.sh` (batched)'* ]] \
  && [[ "$CHECK_N" -eq 4 ]] \
  && ok "followups issue body one-checklist contract" \
  || no "followups issue body contract broken (checkboxes=$CHECK_N)"
grep -qE 'one\*?\*? batched backlog issue|batched backlog issue' docs/FOLLOWUPS.md \
  && ok "FOLLOWUPS.md batch policy" \
  || no "FOLLOWUPS.md batch policy"
grep -q 'product / MVP' docs/FOLLOWUPS.md \
  && grep -q 'Comment-only' docs/FOLLOWUPS.md \
  && ok "FOLLOWUPS.md product Risks-only / Nits comment-only" \
  || no "FOLLOWUPS.md missing Risks-only product policy"
grep -q 'one batched' .cursor/skills/themis-followups/SKILL.md \
  && ok "themis-followups SKILL batch policy" \
  || no "themis-followups SKILL batch policy"
FU_RISKS_ONLY=$(THEMIS_FOLLOWUP_SECTIONS='Risks' python3 scripts/review_followups.py tests/fixtures/review-followups/risks-nits.md --json)
echo "$FU_RISKS_ONLY" | grep -q '"count": 1' && ok "followups Risks-only ignores Nits" || no "followups Risks-only should count=1"
have ".github/workflows/auto-merge.yml"
have ".github/workflows/ci.yml"
grep -q 'Post review comment' .github/workflows/code-review.yml \
  && grep -q 'themis-cursor-review' .github/workflows/code-review.yml \
  && ok "code-review posts themis-cursor-review comment" \
  || no "code-review missing Post review comment"

echo "== central review-rules pack =="
have "review-rules/README.md"
have "review-rules/10-tests-must-have.md"
have "review-rules/20-review-output.md"
have "review-rules/30-change-description.md"
have "review-rules/40-wiring-review-float.md"
have "scripts/build_review_prompt.sh"
chmod +x scripts/build_review_prompt.sh
grep -q 'No new tests' review-rules/10-tests-must-have.md \
  && ok "10-tests-must-have has Blocking bar" \
  || no "10-tests-must-have missing bar"
PROMPT_OUT="$(bash scripts/build_review_prompt.sh --pr 1 --base origin/main --label themis-self --themis-root . --local-rule .cursor/rules/code-review.mdc)"
echo "$PROMPT_OUT" | grep -q 'Shared Themis review rules' \
  && echo "$PROMPT_OUT" | grep -q '10-tests-must-have' \
  && echo "$PROMPT_OUT" | grep -q '20-review-output' \
  && echo "$PROMPT_OUT" | grep -q '30-change-description' \
  && ok "build_review_prompt inlines full pack" \
  || no "build_review_prompt must inline NN-*.md pack"
# Adding a new numbered rule must be picked up without script edits (contract).
TMP_RULE="$(mktemp "$ROOT/review-rules/99-selftest-XXXX.md")"
echo "# selftest rule marker UNIQUE_THEMIS_RULE_PACK" >"$TMP_RULE"
PROMPT2="$(bash scripts/build_review_prompt.sh --pr 1 --base origin/main --label t --themis-root .)"
echo "$PROMPT2" | grep -q 'UNIQUE_THEMIS_RULE_PACK' \
  && ok "new review-rules/NN-*.md auto-included" \
  || no "new NN-*.md must auto-include in prompt"
rm -f "$TMP_RULE"
have "templates/engine-code-review-block.md"
grep -q 'review-rules/10-tests-must-have.md' templates/engine-code-review-block.md \
  && ok "legacy template points at review-rules" \
  || no "legacy template must point at review-rules"
grep -q 'build_review_prompt.sh' docs/WIRING.md \
  && grep -q 'review-rules/' docs/WIRING.md \
  && ok "WIRING documents central pack + builder" \
  || no "WIRING must document build_review_prompt + review-rules"
grep -q 'build_review_prompt.sh' .github/workflows/code-review.yml \
  && ok "themis code-review uses build_review_prompt" \
  || no "themis code-review must use build_review_prompt"
grep -q 'review-rules/' .cursor/skills/themis-code-review/SKILL.md \
  && ok "themis-code-review skill cites review-rules" \
  || no "themis-code-review skill must cite review-rules"

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
