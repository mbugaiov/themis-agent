#!/usr/bin/env bash
# File Themis follow-up sections as ONE batched backlog issue (GitHub Issues or Jira).
# Prefer fixing all items on the source PR; when deferring, batch into a single pickup ticket
# so factory pickup closes them together — never one issue per bullet.
#
# Usage:
#   bash scripts/file_review_followups.sh <PR_NUMBER> [review.md]
#   bash scripts/file_review_followups.sh <PR_NUMBER> --from-comment
#
# Env: THEMIS_REVIEW_MARKER, THEMIS_FOLLOWUP_SECTIONS, THEMIS_FOLLOWUP_DISPOSE_MARKER
#      THEMIS_FOLLOWUP_TRACKER=github|jira (default github)
#      THEMIS_FOLLOWUP_SCM=github|bitbucket (default github)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALLER_PWD="${PWD}"

PR="${1:-}"
SRC="${2:-}"
if [[ -z "$PR" || ! "$PR" =~ ^[0-9]+$ ]]; then
  echo "Usage: file_review_followups.sh <PR_NUMBER> [review.md|--from-comment]" >&2
  exit 2
fi

# Prefer explicit engine repo — never resolve from themis-agent checkout cwd.
if [[ -n "${THEMIS_FOLLOWUP_REPO:-}" ]]; then
  REPO="$THEMIS_FOLLOWUP_REPO"
elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  REPO="$GITHUB_REPOSITORY"
else
  REPO="$(cd "$CALLER_PWD" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
MARKER="${THEMIS_FOLLOWUP_DISPOSE_MARKER:-<!-- themis-review-followups-disposed -->}"
TRACKER="${THEMIS_FOLLOWUP_TRACKER:-github}"
REVIEW_FILE=""
CLEANUP_TMP=""
DISPOSE_TMP=""

cleanup() {
  [[ -n "$CLEANUP_TMP" && -f "$CLEANUP_TMP" ]] && rm -f "$CLEANUP_TMP"
  [[ -n "$DISPOSE_TMP" && -f "$DISPOSE_TMP" ]] && rm -f "$DISPOSE_TMP"
}
trap cleanup EXIT

fetch_comment_review() {
  local tmp
  tmp="$(mktemp)"
  if ! ROOT="$ROOT" REPO="$REPO" python3 -c "
import importlib.util, os, sys
from dataclasses import replace
from pathlib import Path
root = Path(os.environ['ROOT'])
spec = importlib.util.spec_from_file_location('rf', root / 'scripts' / 'review_followups.py')
rf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rf)
spec2 = importlib.util.spec_from_file_location('followups_transport', root / 'scripts' / 'followups_transport.py')
ft = importlib.util.module_from_spec(spec2)
sys.modules['followups_transport'] = ft
spec2.loader.exec_module(ft)
cfg = ft.FollowUpConfig.from_env()
repo = os.environ.get('REPO', '')
if repo and not cfg.github_repo:
    cfg = replace(cfg, github_repo=repo)
t = ft.FollowUpTransport(config=cfg)
b = t.fetch_latest_review(int(sys.argv[1]), rf.review_marker())
if not b:
    sys.exit(1)
Path(sys.argv[2]).write_text(b, encoding='utf-8')
" "$PR" "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  echo "$tmp"
}

# Resolve paths against caller cwd (before any cd into themis root).
if [[ "$SRC" == "--from-comment" ]]; then
  REVIEW_FILE="$(fetch_comment_review || true)"
  CLEANUP_TMP="$REVIEW_FILE"
elif [[ -n "$SRC" ]]; then
  if [[ "$SRC" = /* && -f "$SRC" ]]; then
    REVIEW_FILE="$SRC"
  elif [[ -f "$CALLER_PWD/$SRC" ]]; then
    REVIEW_FILE="$CALLER_PWD/$SRC"
  elif [[ -f "$SRC" ]]; then
    REVIEW_FILE="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"
  fi
elif [[ -f "$CALLER_PWD/review.md" ]]; then
  REVIEW_FILE="$CALLER_PWD/review.md"
elif [[ -f "$ROOT/review.md" ]]; then
  REVIEW_FILE="$ROOT/review.md"
else
  REVIEW_FILE="$(fetch_comment_review || true)"
  CLEANUP_TMP="$REVIEW_FILE"
fi

if [[ -z "${REVIEW_FILE:-}" || ! -f "$REVIEW_FILE" ]]; then
  echo "No review.md / PR review comment found for #$PR" >&2
  exit 1
fi

JSON="$(python3 "$ROOT/scripts/review_followups.py" "$REVIEW_FILE" --json)"
COUNT="$(echo "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("count") or 0)')"
FP="$(echo "$JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fingerprint") or "empty")')"

EXISTING="$(python3 "$ROOT/scripts/followups_transport.py" find-dispose "$PR" \
  --marker "$MARKER" --fingerprint "$FP" 2>/dev/null || true)"
if [[ -n "$EXISTING" ]]; then
  echo "FOLLOWUPS_ALREADY_DISPOSED comment_id=$EXISTING fingerprint=$FP"
  exit 0
fi

if [[ "$TRACKER" == "github" && -n "$REPO" ]]; then
  gh label create themis-followup -R "$REPO" -c "0E8A16" -d "From Themis Suggestions/Risks" 2>/dev/null || true
  gh label create backlog -R "$REPO" -c "FBCA04" -d "Backlog pickup" 2>/dev/null || true
fi

if [[ "$COUNT" -eq 0 ]]; then
  DISPOSE_TMP="$(mktemp)"
  python3 -c "
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('followups_transport', Path('$ROOT/scripts/followups_transport.py'))
ft = importlib.util.module_from_spec(spec)
sys.modules['followups_transport'] = ft
spec.loader.exec_module(ft)
print(ft.build_dispose_body('$MARKER', '$FP'))
" >"$DISPOSE_TMP"
  python3 "$ROOT/scripts/followups_transport.py" post-dispose "$PR" --body-file "$DISPOSE_TMP" >/dev/null
  echo "FOLLOWUPS_NONE"
  exit 0
fi

echo "Filing ONE batched follow-up issue ($COUNT item(s)) via $TRACKER from PR #${PR}..."

BODY_ISSUE="$(python3 "$ROOT/scripts/review_followups.py" "$REVIEW_FILE" \
  --issue-body --pr "$PR" --repo "${REPO:-unknown/repo}")"

TITLE_COUNT="$([[ "$COUNT" -eq 1 ]] && echo '1 item' || echo "${COUNT} items")"
TITLE="Themis follow-ups (PR #${PR}): ${TITLE_COUNT} — fix together in one PR"

BODY_TMP="$(mktemp)"
echo "$BODY_ISSUE" >"$BODY_TMP"
if [[ "$TRACKER" == "jira" ]]; then
  ISSUE_URL="$(python3 "$ROOT/scripts/followups_transport.py" file-issue \
    --title "$TITLE" \
    --body-file "$BODY_TMP" \
    --label themis-followup \
    --label impl-dev)"
else
  ISSUE_URL="$(python3 "$ROOT/scripts/followups_transport.py" file-issue \
    --title "$TITLE" \
    --body-file "$BODY_TMP" \
    --label themis-followup \
    --label backlog 2>/dev/null || \
    python3 "$ROOT/scripts/followups_transport.py" file-issue \
    --title "$TITLE" \
    --body-file "$BODY_TMP" \
    --label themis-followup)"
fi
rm -f "$BODY_TMP"
ISSUE_URL="$(echo "$ISSUE_URL" | tr -d '\r' | tail -1)"
echo "  batched → $ISSUE_URL"

DISPOSE_TMP="$(mktemp)"
python3 -c "
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('followups_transport', Path('$ROOT/scripts/followups_transport.py'))
ft = importlib.util.module_from_spec(spec)
sys.modules['followups_transport'] = ft
spec.loader.exec_module(ft)
print(ft.build_dispose_body('$MARKER', '$FP', filed=True, issue_url='''$ISSUE_URL''', count=$COUNT))
" >"$DISPOSE_TMP"
python3 "$ROOT/scripts/followups_transport.py" post-dispose "$PR" --body-file "$DISPOSE_TMP" >/dev/null

echo "FOLLOWUPS_FILED count=$COUNT issues=1 fingerprint=$FP url=$ISSUE_URL"
