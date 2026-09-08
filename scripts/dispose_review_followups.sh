#!/usr/bin/env bash
# Dispose every gated Themis follow-up as fixed, accepted, or deferred.
#
# Usage:
#   bash scripts/dispose_review_followups.sh <PR> <triage.json> [review.md|--from-comment]
# Triage JSON:
#   [{"item": 1, "disposition": "fixed|accepted|deferred", "rationale": "..."}]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALLER_PWD="$PWD"

PR="${1:-}"
TRIAGE_SRC="${2:-}"
REVIEW_SRC="${3:---from-comment}"
if [[ -z "$PR" || ! "$PR" =~ ^[0-9]+$ || -z "$TRIAGE_SRC" ]]; then
  echo "Usage: dispose_review_followups.sh <PR> <triage.json> [review.md|--from-comment]" >&2
  exit 2
fi

resolve_file() {
  local value="$1"
  if [[ "$value" = /* && -f "$value" ]]; then
    printf '%s\n' "$value"
  elif [[ -f "$CALLER_PWD/$value" ]]; then
    printf '%s\n' "$CALLER_PWD/$value"
  else
    return 1
  fi
}

TRIAGE_FILE="$(resolve_file "$TRIAGE_SRC" || true)"
if [[ -z "$TRIAGE_FILE" ]]; then
  echo "Triage file not found: $TRIAGE_SRC" >&2
  exit 2
fi

if [[ -n "${THEMIS_FOLLOWUP_REPO:-}" ]]; then
  REPO="$THEMIS_FOLLOWUP_REPO"
elif [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
  REPO="$GITHUB_REPOSITORY"
else
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
REVIEW_MARKER="${THEMIS_REVIEW_MARKER:-<!-- themis-cursor-review -->}"
DISPOSE_MARKER="${THEMIS_FOLLOWUP_DISPOSE_MARKER:-<!-- themis-review-followups-disposed -->}"

REVIEW_TMP=""
PLAN_TMP="$(mktemp)"
DEFERRED_TMP="$(mktemp)"
BODY_TMP="$(mktemp)"
cleanup() {
  [[ -n "$REVIEW_TMP" && -f "$REVIEW_TMP" ]] && rm -f "$REVIEW_TMP"
  rm -f "$PLAN_TMP" "$DEFERRED_TMP" "$BODY_TMP"
}
trap cleanup EXIT

if [[ "$REVIEW_SRC" == "--from-comment" ]]; then
  REVIEW_TMP="$(mktemp)"
  THEMIS_FOLLOWUP_REPO="$REPO" python3 "$ROOT/scripts/followups_transport.py" \
    fetch-review "$PR" --marker "$REVIEW_MARKER" >"$REVIEW_TMP"
  REVIEW_FILE="$REVIEW_TMP"
else
  REVIEW_FILE="$(resolve_file "$REVIEW_SRC" || true)"
  if [[ -z "$REVIEW_FILE" ]]; then
    echo "Review file not found: $REVIEW_SRC" >&2
    exit 2
  fi
fi

# Validate the complete triage before checking or posting disposal. Invalid acceptance
# therefore cannot create a dispose comment or a backlog issue.
PLAN_SUMMARY="$(python3 "$ROOT/scripts/dispose_review_followups.py" plan \
  "$REVIEW_FILE" "$TRIAGE_FILE" --output "$PLAN_TMP" \
  --deferred-review "$DEFERRED_TMP")"
FP="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["fingerprint"])' <<<"$PLAN_SUMMARY")"
COUNT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])' <<<"$PLAN_SUMMARY")"
DEFERRED_COUNT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["deferred_count"])' <<<"$PLAN_SUMMARY")"

EXISTING="$(THEMIS_FOLLOWUP_REPO="$REPO" \
  python3 "$ROOT/scripts/followups_transport.py" find-dispose "$PR" \
  --marker "$DISPOSE_MARKER" --fingerprint "$FP" 2>/dev/null || true)"
if [[ -n "$EXISTING" ]]; then
  echo "FOLLOWUPS_ALREADY_DISPOSED comment_id=$EXISTING fingerprint=$FP"
  exit 0
fi

if [[ "$DEFERRED_COUNT" -gt 0 ]]; then
  THEMIS_FOLLOWUP_REPO="$REPO" \
  THEMIS_FOLLOWUP_FINGERPRINT_OVERRIDE="$FP" \
  THEMIS_FOLLOWUP_TRIAGE_PLAN="$PLAN_TMP" \
    bash "$ROOT/scripts/file_review_followups.sh" "$PR" "$DEFERRED_TMP"
  exit 0
fi

python3 "$ROOT/scripts/dispose_review_followups.py" body "$PLAN_TMP" \
  --marker "$DISPOSE_MARKER" --fingerprint "$FP" >"$BODY_TMP"
THEMIS_FOLLOWUP_REPO="$REPO" \
  python3 "$ROOT/scripts/followups_transport.py" post-dispose "$PR" \
  --body-file "$BODY_TMP" >/dev/null
echo "FOLLOWUPS_DISPOSED count=$COUNT deferred=0 fingerprint=$FP"
