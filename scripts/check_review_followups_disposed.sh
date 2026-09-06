#!/usr/bin/env bash
# After Themis is green: ensure follow-up sections were fixed in the PR *or*
# filed as backlog issues (disposal comment for *this* review fingerprint).
#
# Usage: bash scripts/check_review_followups_disposed.sh <PR_NUMBER>
#
# Env (set by each engine wrapper):
#   THEMIS_REVIEW_MARKER
#   THEMIS_FOLLOWUP_SECTIONS
#   THEMIS_FOLLOWUP_DISPOSE_MARKER
#   THEMIS_FOLLOWUP_REPO   optional owner/name (preferred over gh from this checkout)
#   THEMIS_FOLLOWUP_SCM    github|bitbucket (default github)
#   GITHUB_REPOSITORY      used in Actions when set to the *engine* repo
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALLER_PWD="${PWD}"

PR="${1:-}"
if [[ -z "$PR" || ! "$PR" =~ ^[0-9]+$ ]]; then
  echo "Usage: check_review_followups_disposed.sh <PR_NUMBER>" >&2
  exit 2
fi

# Never `gh repo view` from themis-agent checkout — that would target the wrong repo.
if [[ -n "${THEMIS_FOLLOWUP_REPO:-}" ]]; then
  REPO="$THEMIS_FOLLOWUP_REPO"
elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  REPO="$GITHUB_REPOSITORY"
else
  REPO="$(cd "$CALLER_PWD" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
MARKER="${THEMIS_FOLLOWUP_DISPOSE_MARKER:-<!-- themis-review-followups-disposed -->}"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

ERR="$(mktemp)"
if ! REPO="$REPO" python3 "$ROOT/scripts/review_followups.py" --from-pr "$PR" --repo "${REPO:-placeholder/repo}" --json >"$TMP" 2>"$ERR"; then
  echo "FOLLOWUPS_CHECK_FAIL — no review comment found after green checks (fail-closed)." >&2
  cat "$ERR" >&2 || true
  rm -f "$ERR"
  exit 1
fi
rm -f "$ERR"

JSON="$(cat "$TMP")"
COUNT="$(echo "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("count") or 0)')"
FP="$(echo "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fingerprint") or "empty")')"

if [[ "$COUNT" -eq 0 ]]; then
  echo "FOLLOWUPS_CHECK_OK — no follow-up items"
  exit 0
fi

DISPOSED="$(python3 "$ROOT/scripts/followups_transport.py" find-dispose "$PR" \
  --marker "$MARKER" --fingerprint "$FP" 2>/dev/null || true)"

if [[ -n "$DISPOSED" ]]; then
  echo "FOLLOWUPS_CHECK_OK — disposed (comment $DISPOSED, fp=$FP), open items were $COUNT"
  exit 0
fi

echo "FOLLOWUPS_CHECK_FAIL — $COUNT follow-up item(s) not disposed." >&2
echo "Either fix them in the PR, or run (engine wrapper):" >&2
echo "  bash scripts/file_review_followups.sh ${PR} --from-comment" >&2
exit 1
