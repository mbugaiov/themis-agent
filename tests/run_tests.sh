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

echo "== scan self (engine) =="
if bash scripts/isolation_scan.sh --mode engine --root "$ROOT"; then
  ok "self scan clean"
else
  no "self scan should be clean"
fi

echo "== follow-ups =="
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

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
