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
unset THEMIS_FOLLOWUP_SECTIONS THEMIS_REVIEW_MARKER THEMIS_FOLLOWUP_DISPOSE_MARKER \
  THEMIS_FOLLOWUP_TRACKER THEMIS_FOLLOWUP_SCM THEMIS_FOLLOWUP_BB_REPO \
  BITBUCKET_WORKSPACE BITBUCKET_REPO_SLUG JIRA_BASE_URL JIRA_PROJECT_KEY \
  THEMIS_FOLLOWUP_JIRA_EPIC
for f in scripts/review_followups.py scripts/followups_transport.py \
  scripts/dispose_review_followups.py scripts/dispose_review_followups.sh \
  scripts/check_review_followups_disposed.sh \
  scripts/file_review_followups.sh docs/FOLLOWUPS.md; do
  have "$f"
done
chmod +x scripts/check_review_followups_disposed.sh scripts/file_review_followups.sh \
  scripts/dispose_review_followups.py scripts/dispose_review_followups.sh \
  scripts/review_followups.py scripts/followups_transport.py
FU_NONE=$(python3 scripts/review_followups.py tests/fixtures/review-followups/none.md --json)
echo "$FU_NONE" | grep -q '"count": 0' && ok "followups none" || no "followups none"
FU_LGTM=$(python3 scripts/review_followups.py tests/fixtures/review-followups/none-with-lgtm.md --json)
echo "$FU_LGTM" | grep -q '"count": 0' && ok "followups none-with-lgtm" || no "followups none-with-lgtm"
FU_MIX=$(python3 scripts/review_followups.py tests/fixtures/review-followups/mixed.md --json)
echo "$FU_MIX" | grep -q '"count": 4' && ok "followups mixed count=4" || no "followups mixed"
MIX_FP=$(echo "$FU_MIX" | python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])')
[[ "$MIX_FP" == "c0b1fd20198917df" ]] && ok "followups mixed fingerprint" || no "followups fingerprint drift ($MIX_FP)"
FU_RN=$(THEMIS_FOLLOWUP_SECTIONS='Risks,Nits' python3 scripts/review_followups.py tests/fixtures/review-followups/risks-nits.md --json)
# Use [[ ]] not echo|grep — pipefail + grep -q → Broken pipe false fail in CI.
[[ "$FU_RN" == *'"count": 2'* ]] && ok "followups Risks+Nits" || no "followups Risks+Nits"
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
if python3 -c 'import json,sys; d=json.load(sys.stdin); raise SystemExit(0 if d.get("count")==1 else 1)' <<<"$FU_RISKS_ONLY"; then
  ok "followups Risks-only ignores Nits"
else
  no "followups Risks-only should count=1"
fi
python3 tests/test_followups_transport.py >/dev/null \
  && ok "followups transport unit tests" \
  || no "followups transport unit tests"
python3 tests/test_dispose_review_followups.py >/dev/null \
  && ok "followups triage unit/contract tests" \
  || no "followups triage unit/contract tests"
BAD_TRIAGE=$(mktemp)
printf '%s\n' \
  '[{"item":1,"disposition":"accepted"},{"item":2,"disposition":"deferred"},{"item":3,"disposition":"deferred"},{"item":4,"disposition":"deferred"}]' \
  >"$BAD_TRIAGE"
BAD_TRIAGE_EC=0
BAD_TRIAGE_OUT=$(THEMIS_FOLLOWUP_REPO=owner/demo \
  bash scripts/dispose_review_followups.sh 42 "$BAD_TRIAGE" \
  tests/fixtures/review-followups/mixed.md 2>&1) || BAD_TRIAGE_EC=$?
rm -f "$BAD_TRIAGE"
[[ "$BAD_TRIAGE_EC" -ne 0 ]] \
  && [[ "$BAD_TRIAGE_OUT" == *'accepted item 1 requires a rationale'* ]] \
  && [[ "$BAD_TRIAGE_OUT" != *'FOLLOWUPS_DISPOSED'* ]] \
  && [[ "$BAD_TRIAGE_OUT" != *'FOLLOWUPS_FILED'* ]] \
  && ok "accepted without rationale fails before dispose/file" \
  || no "accepted without rationale must fail before side effects"
HAPPY_DIR=$(mktemp -d)
REAL_PYTHON=$(command -v python3)
mkdir -p "$HAPPY_DIR/bin"
cat >"$HAPPY_DIR/bin/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == */followups_transport.py ]]; then
  case "${2:-}" in
    find-dispose)
      exit 0
      ;;
    post-dispose)
      shift 2
      while [[ "$#" -gt 0 ]]; do
        if [[ "$1" == "--body-file" ]]; then
          cp "$2" "$CAPTURE_DISPOSE_BODY"
          echo "posted comment_id=test"
          exit 0
        fi
        shift
      done
      exit 2
      ;;
  esac
fi
exec "$REAL_PYTHON" "$@"
EOF
chmod +x "$HAPPY_DIR/bin/python3"
cat >"$HAPPY_DIR/triage.json" <<'EOF'
[
  {"item":1,"disposition":"fixed","rationale":"commit abc123 renames helper"},
  {"item":2,"disposition":"fixed","rationale":"commit abc123 adds parser test"},
  {"item":3,"disposition":"fixed","rationale":"commit abc123 removes product label"},
  {"item":4,"disposition":"fixed","rationale":"commit abc123 keeps linger"}
]
EOF
HAPPY_OUT=$(PATH="$HAPPY_DIR/bin:$PATH" REAL_PYTHON="$REAL_PYTHON" \
  CAPTURE_DISPOSE_BODY="$HAPPY_DIR/dispose.md" THEMIS_FOLLOWUP_REPO=owner/demo \
  bash scripts/dispose_review_followups.sh 42 "$HAPPY_DIR/triage.json" \
  tests/fixtures/review-followups/mixed.md 2>&1)
HAPPY_BODY=$(cat "$HAPPY_DIR/dispose.md" 2>/dev/null || true)
[[ "$HAPPY_OUT" == *'FOLLOWUPS_DISPOSED count=4 deferred=0'* ]] \
  && [[ "$HAPPY_OUT" != *'FOLLOWUPS_FILED'* ]] \
  && [[ "$HAPPY_BODY" == *'<!-- themis-review-followups-disposed -->'* ]] \
  && [[ "$HAPPY_BODY" == *'<!-- fingerprint=c0b1fd20198917df -->'* ]] \
  && [[ "$HAPPY_BODY" == *'| # | Review item | Disposition | Rationale |'* ]] \
  && ok "all-fixed shell path posts structured dispose only" \
  || no "all-fixed shell path must post structured dispose without filing"
rm -rf "$HAPPY_DIR"
grep -q 'THEMIS_FOLLOWUP_TRIAGE_PLAN' scripts/file_review_followups.sh \
  && grep -q 'file_review_followups.sh' scripts/dispose_review_followups.sh \
  && ok "deferred triage reuses one batched filing path" \
  || no "deferred triage must reuse file_review_followups.sh"
grep -q 'marker + fingerprint contract' docs/FOLLOWUPS.md \
  && grep -q 'find-dispose' scripts/check_review_followups_disposed.sh \
  && ok "historical marker+fingerprint dispose gate preserved" \
  || no "dispose gate compatibility contract missing"
# Regression: importlib load used by dispose gate must register sys.modules (dataclasses).
python3 -c "
import importlib.util, sys
from pathlib import Path
p = Path('scripts/followups_transport.py')
spec = importlib.util.spec_from_file_location('followups_transport', p)
m = importlib.util.module_from_spec(spec)
sys.modules['followups_transport'] = m
spec.loader.exec_module(m)
assert m.FollowUpConfig.from_env().scm == 'github'
" && ok "followups_transport importlib+sys.modules load" \
  || no "followups_transport importlib load broken"
grep -q 'THEMIS_FOLLOWUP_TRACKER' docs/FOLLOWUPS.md \
  && grep -q 'bitbucket' docs/FOLLOWUPS.md \
  && ok "FOLLOWUPS.md jira+bitbucket matrix" \
  || no "FOLLOWUPS.md jira+bitbucket matrix"
grep -q 'THEMIS_FOLLOWUP_SCM' docs/WIRING.md \
  && ok "WIRING.md follow-up transport matrix" \
  || no "WIRING.md follow-up transport matrix"
have ".github/workflows/auto-merge.yml"
have ".github/workflows/ci.yml"
grep -q 'Post review comment' .github/workflows/code-review.yml \
  && grep -q 'themis-cursor-review' .github/workflows/code-review.yml \
  && ok "code-review posts themis-cursor-review comment" \
  || no "code-review missing Post review comment"

# Cursor Router Optimize For disabled for team — CI must pin an explicit model.
grep -q -- '--model composer-2.5' .github/workflows/code-review.yml \
  && grep -q -- '--model composer-2.5' scripts/ci_isolation.sh \
  && ok "CI pins composer-2.5 (Optimize For workaround)" \
  || no "CI missing composer-2.5 model pin"
# Cost: never fall back to composer-2.5-fast (≈6× input/output vs composer-2.5).
! grep -q 'composer-2.5-fast' .github/workflows/code-review.yml \
  && ! grep -q 'composer-2.5-fast' scripts/ci_isolation.sh \
  && ok "CI never uses composer-2.5-fast" \
  || no "CI still references composer-2.5-fast"

echo "== central review-rules pack =="
have "review-rules/README.md"
have "review-rules/10-tests-must-have.md"
have "review-rules/20-review-output.md"
have "review-rules/30-change-description.md"
have "review-rules/40-wiring-review-float.md"
have "review-rules/50-reuse-existing.md"
have "scripts/build_review_prompt.sh"
chmod +x scripts/build_review_prompt.sh
grep -q 'No new tests' review-rules/10-tests-must-have.md \
  && ok "10-tests-must-have has Blocking bar" \
  || no "10-tests-must-have missing bar"
grep -q 'reuse existing' review-rules/50-reuse-existing.md \
  && grep -q 'Search the merge target\|search the merge target\|destination tree' review-rules/50-reuse-existing.md \
  && ok "50-reuse-existing requires base-tree search" \
  || no "50-reuse-existing missing reuse / base search bar"
grep -q 'Entry-only twin' review-rules/50-reuse-existing.md \
  && grep -q 'parametrized' review-rules/50-reuse-existing.md \
  && grep -q 'Not a Suggestion' review-rules/50-reuse-existing.md \
  && grep -A2 'Block on' review-rules/50-reuse-existing.md | head -1 >/dev/null \
  && ok "50-reuse-existing marks entry-only page/fixture twins Blocking" \
  || no "50-reuse-existing must Blocking entry-only twins (not Suggestion)"
# Negative: Suggestions-only section must not soft-pedal entry-only twins
SUGG_SEC=$(awk '/^## Suggestions only/,/^## What/' review-rules/50-reuse-existing.md)
! grep -qiE '\btab\b|plant/|parametrized fixture|entry-only' <<<"$SUGG_SEC" \
  && ok "50-reuse-existing Suggestions section does not soft-pedal entry-only twins" \
  || no "Suggestions must not list entry-only tab twins as non-blocking"
ec=0; bash scripts/build_review_prompt.sh --themis-root . >/dev/null 2> /tmp/themis-brp-pr.err || ec=$?
[[ "$ec" -eq 2 ]] && grep -q -- '--pr' /tmp/themis-brp-pr.err \
  && ok "builder missing --pr exits 2" \
  || no "builder must exit 2 without --pr"
ec=0; bash scripts/build_review_prompt.sh --pr 1 --themis-root /tmp/themis-no-rules-$$ >/dev/null 2> /tmp/themis-brp-dir.err || ec=$?
[[ "$ec" -eq 2 ]] && grep -q 'missing review-rules' /tmp/themis-brp-dir.err \
  && ok "builder missing review-rules/ exits 2" \
  || no "builder must exit 2 when review-rules/ missing"
EMPTY_RULES="$(mktemp -d)"
mkdir -p "$EMPTY_RULES/review-rules"
ec=0; bash scripts/build_review_prompt.sh --pr 1 --themis-root "$EMPTY_RULES" >/dev/null 2> /tmp/themis-brp-empty.err || ec=$?
[[ "$ec" -eq 2 ]] && grep -q 'no review-rules' /tmp/themis-brp-empty.err \
  && ok "builder zero NN-*.md exits 2" \
  || no "builder must exit 2 with empty review-rules/"
rm -rf "$EMPTY_RULES"
PROMPT_OUT="$(bash scripts/build_review_prompt.sh --pr 1 --base origin/main --label themis-self --themis-root . --local-rule .cursor/rules/code-review.mdc)"
if grep -q 'Shared Themis review rules' <<<"$PROMPT_OUT" \
  && grep -q '10-tests-must-have' <<<"$PROMPT_OUT" \
  && grep -q '20-review-output' <<<"$PROMPT_OUT" \
  && grep -q '30-change-description' <<<"$PROMPT_OUT" \
  && grep -q '50-reuse-existing' <<<"$PROMPT_OUT"; then
  ok "build_review_prompt inlines full pack"
else
  no "build_review_prompt must inline NN-*.md pack"
fi
# Adding a new numbered rule must be picked up without script edits (contract).
TMP_RULE="$(mktemp "$ROOT/review-rules/99-selftest-XXXX.md")"
echo "# selftest rule marker UNIQUE_THEMIS_RULE_PACK" >"$TMP_RULE"
PROMPT2="$(bash scripts/build_review_prompt.sh --pr 1 --base origin/main --label t --themis-root .)"
if grep -q 'UNIQUE_THEMIS_RULE_PACK' <<<"$PROMPT2"; then
  ok "new review-rules/NN-*.md auto-included"
else
  no "new NN-*.md must auto-include in prompt"
fi
rm -f "$TMP_RULE"
have "templates/engine-code-review-block.md"
grep -q 'review-rules/10-tests-must-have.md' templates/engine-code-review-block.md \
  && grep -q 'MUST-HAVE → Blocking' templates/engine-code-review-block.md \
  && ok "legacy template points at review-rules + Blocking bar" \
  || no "legacy template must keep MUST-HAVE Blocking reminder"
grep -q 'review-rules/10-tests-must-have.md' .cursor/rules/code-review.mdc \
  && ok "code-review.mdc cites shared tests MUST-HAVE" \
  || no "code-review.mdc must cite 10-tests-must-have"
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
