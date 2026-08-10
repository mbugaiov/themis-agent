#!/usr/bin/env bash
# File Themis follow-up sections as ONE GitHub backlog issue on the *same* repo as the PR.
# Prefer fixing all items on the source PR; when deferring, batch into a single pickup ticket
# so Hephaestus/dev closes them together — never one issue per bullet.
#
# Usage:
#   bash scripts/file_review_followups.sh <PR_NUMBER> [review.md]
#   bash scripts/file_review_followups.sh <PR_NUMBER> --from-comment
#
# Env: THEMIS_REVIEW_MARKER, THEMIS_FOLLOWUP_SECTIONS, THEMIS_FOLLOWUP_DISPOSE_MARKER
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
  REPO="$(cd "$CALLER_PWD" && gh repo view --json nameWithOwner -q .nameWithOwner)"
fi
MARKER="${THEMIS_FOLLOWUP_DISPOSE_MARKER:-<!-- themis-review-followups-disposed -->}"
REVIEW_FILE=""
CLEANUP_TMP=""

cleanup() {
  [[ -n "$CLEANUP_TMP" && -f "$CLEANUP_TMP" ]] && rm -f "$CLEANUP_TMP"
}
trap cleanup EXIT

fetch_comment_review() {
  local tmp
  tmp="$(mktemp)"
  if ! ROOT="$ROOT" python3 -c "
import importlib.util, os, sys
from pathlib import Path
root = Path(os.environ['ROOT'])
spec = importlib.util.spec_from_file_location('rf', root / 'scripts' / 'review_followups.py')
rf = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rf)
b = rf.fetch_latest_themis_review(sys.argv[1], int(sys.argv[2]))
if not b:
    sys.exit(1)
Path(sys.argv[3]).write_text(b, encoding='utf-8')
" "$REPO" "$PR" "$tmp"; then
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

EXISTING="$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate \
  --jq ".[] | select(.body|contains(\"${MARKER}\")) | select(.body|contains(\"fingerprint=${FP}\")) | .id" \
  2>/dev/null | head -1 || true)"
if [[ -n "$EXISTING" ]]; then
  echo "FOLLOWUPS_ALREADY_DISPOSED comment_id=$EXISTING fingerprint=$FP"
  exit 0
fi

gh label create themis-followup -R "$REPO" -c "0E8A16" -d "From Themis Suggestions/Risks" 2>/dev/null || true
gh label create backlog -R "$REPO" -c "FBCA04" -d "Backlog pickup" 2>/dev/null || true

if [[ "$COUNT" -eq 0 ]]; then
  BODY="$(cat <<EOF
${MARKER}
<!-- fingerprint=${FP} -->
## Themis follow-ups disposed

No follow-up items to file (or sections are \`None.\`).
EOF
)"
  gh api "repos/${REPO}/issues/${PR}/comments" -f body="$BODY" >/dev/null
  echo "FOLLOWUPS_NONE"
  exit 0
fi

echo "Filing ONE batched follow-up issue ($COUNT item(s)) on $REPO from PR #$PR…"

BODY_ISSUE="$(echo "$JSON" | PR="$PR" REPO="$REPO" FP="$FP" python3 -c '
import json, os, sys
j = json.load(sys.stdin)
pr = os.environ["PR"]
repo = os.environ["REPO"]
fp = os.environ["FP"]
count = j.get("count") or 0
lines = [
    f"## From Themis review on PR #{pr}",
    "",
    f"**Source PR:** https://github.com/{repo}/pull/{pr}",
    f"**Fingerprint:** `{fp}`",
    f"**Items:** {count}",
    "",
    "Fix **all** checklist items in **one** follow-up PR (do not open one PR per bullet).",
    "",
    "### Checklist",
    "",
]
for it in j.get("items") or []:
    kind = (it.get("kind") or "Follow-up").strip()
    text = (it.get("text") or "").strip().replace("\r\n", "\n")
    parts = text.split("\n", 1)
    head = parts[0].strip() or "(empty)"
    lines.append(f"- [ ] **{kind}:** {head}")
    if len(parts) > 1 and parts[1].strip():
        for ln in parts[1].strip().split("\n"):
            lines.append(f"  {ln}")
    lines.append("")
lines.extend([
    "---",
    "",
    "Filed by themis-agent `file_review_followups.sh` (batched) — pick up via `themis-followup` / `backlog`.",
])
print("\n".join(lines))
')"

TITLE="Themis follow-ups (PR #${PR}): ${COUNT} items — fix together in one PR"

if ! ISSUE_URL="$(gh issue create -R "$REPO" \
  --title "$TITLE" \
  --label "themis-followup" --label "backlog" \
  --body "$BODY_ISSUE" 2>/dev/null)"; then
  ISSUE_URL="$(gh issue create -R "$REPO" \
    --title "$TITLE" \
    --body "$BODY_ISSUE")"
fi
ISSUE_URL="$(echo "$ISSUE_URL" | tr -d '\r' | tail -1)"
echo "  batched → $ISSUE_URL"

gh api "repos/${REPO}/issues/${PR}/comments" -f body="$(cat <<EOF
${MARKER}
<!-- fingerprint=${FP} -->
## Themis follow-ups disposed

Follow-ups from review were filed as **one** backlog issue (not fixed in this PR).
Pick up and fix **all** checklist items in a **single** PR:

- ${ISSUE_URL}

Label: \`themis-followup\` / \`backlog\`.
EOF
)" >/dev/null

echo "FOLLOWUPS_FILED count=$COUNT issues=1 fingerprint=$FP url=$ISSUE_URL"
