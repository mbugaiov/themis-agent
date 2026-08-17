#!/usr/bin/env bash
# CI entry: deterministic isolation scan + optional LLM isolation pass.
#
# Usage (from the repo under review):
#   bash /path/to/themis-agent/scripts/ci_isolation.sh \
#     --mode engine|product [--peer-pattern REGEX] [--base origin/main] [--no-llm]
#
# Env: CURSOR_API_KEY (optional — skips LLM if unset)
# Exit 0 = clean. Exit 1 = scan or LLM blockers.
set -euo pipefail

THEMIS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="engine"
PEER=""
BASE=""
ROOT="$(pwd)"
RUN_LLM=1
OUT="isolation-review.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --peer-pattern) PEER="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --no-llm) RUN_LLM=0; shift ;;
    --out) OUT="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: ci_isolation.sh --mode engine|product [--peer-pattern REGEX] [--base origin/<base>] [--no-llm]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

cd "$ROOT"
if [[ -n "$BASE" ]]; then
  git fetch origin "${BASE#origin/}" --quiet 2>/dev/null || true
fi

SCAN_ARGS=(--mode "$MODE" --root "$ROOT")
[[ -n "$BASE" ]] && SCAN_ARGS+=(--base "$BASE")
[[ -n "$PEER" ]] && SCAN_ARGS+=(--peer-pattern "$PEER")

echo "== Themis isolation scan (deterministic) =="
set +e
bash "$THEMIS_ROOT/scripts/isolation_scan.sh" "${SCAN_ARGS[@]}"
SCAN_EC=$?
set -e

if [[ "$RUN_LLM" -eq 0 || -z "${CURSOR_API_KEY:-}" ]]; then
  if [[ "$SCAN_EC" -ne 0 ]]; then
    echo "isolation_scan FAILED (LLM skipped)" >&2
    exit 1
  fi
  if [[ -z "${CURSOR_API_KEY:-}" && "$RUN_LLM" -eq 1 ]]; then
    echo "WARN: CURSOR_API_KEY unset — deterministic scan only"
  fi
  cat > "$OUT" <<'EOF'
LGTM - no blocking issues found.
EOF
  echo "isolation (Themis): PASS (scan only)"
  exit 0
fi

echo "== Themis isolation LLM pass =="
DIFF=""
NAMEONLY=""
if [[ -n "$BASE" ]]; then
  DIFF="$(git --no-pager diff "$BASE"...HEAD 2>/dev/null || true)"
  NAMEONLY="$(git --no-pager diff --name-only "$BASE"...HEAD 2>/dev/null || true)"
fi
if [[ -z "$DIFF" ]]; then
  cat > "$OUT" <<'EOF'
LGTM - no blocking issues found.
EOF
else
  # Vendored skill packs blow past OS ARG_MAX for `agent -p "$PROMPT"`.
  # Prefer a control-plane-only diff; if still huge, fall back to scan-only LGTM
  # (deterministic isolation_scan already ran above).
  MAX_CHARS=50000
  DIFF_LEN=${#DIFF}
  if [[ "$DIFF_LEN" -gt "$MAX_CHARS" ]]; then
    echo "WARN: full diff ${DIFF_LEN} chars — using control-plane slice for LLM"
    CTRL_DIFF="$(git --no-pager diff "$BASE"...HEAD -- . \
      ':(exclude).agents/skills' \
      ':(exclude)node_modules' \
      2>/dev/null || true)"
    DIFF="$(printf '%s\n' \
      "[Large diff: ${DIFF_LEN} chars — vendored .agents/skills omitted for LLM]" \
      "Changed files:" \
      "$NAMEONLY" \
      "" \
      "Control-plane diff:" \
      "$CTRL_DIFF")"
  fi
  if [[ ${#DIFF} -gt "$MAX_CHARS" ]]; then
    echo "WARN: control-plane diff still ${#DIFF} chars — isolation LLM skipped (scan already OK unless SCAN_EC≠0)"
    if [[ "$SCAN_EC" -ne 0 ]]; then
      echo "isolation_scan FAILED" >&2
      exit 1
    fi
    cat > "$OUT" <<'EOF'
LGTM - no blocking issues found.
EOF
    echo "isolation (Themis): PASS (scan only — diff too large for LLM argv)"
    exit 0
  fi
  PROMPT="$(cat <<EOF
You are Themis Isolation reviewer (portable engine). Mode=${MODE}.
Focus ONLY on: customer/project leakage across tenants, secrets, host paths,
engine portability, docs/skills/rules consistency. Do NOT review language style or product architecture.
Do NOT Blocking-flag unpinned review-job themis checkout vs pinned isolation/ensure (WIRING float-pack contract).
Follow skill themis-isolation. Produce exactly:
## Summary
## Blocking issues
## Suggestions
Or single line: LGTM - no blocking issues found.
Peer pattern (product mode): ${PEER:-none}
Diff:
${DIFF}
EOF
)"
  REVIEW_BIN="agent"
  command -v agent >/dev/null 2>&1 || REVIEW_BIN="cursor-agent"
  set +e
  "$REVIEW_BIN" --force --api-key "$CURSOR_API_KEY" --output-format text -p "$PROMPT" > "$OUT" 2>isolation.err || true
  set -e
  if [[ -s isolation.err ]]; then
    echo "----- isolation LLM stderr -----"
    cat isolation.err
  fi
  [[ -s "$OUT" ]] || echo "Cursor review produced no output (see build log above)." > "$OUT"
fi

echo "----- isolation review -----"
cat "$OUT"

bash "$THEMIS_ROOT/scripts/check_review_gate.sh" "$OUT"
LLM_EC=$?

if [[ "$SCAN_EC" -ne 0 ]]; then
  echo "isolation_scan FAILED" >&2
  exit 1
fi
exit "$LLM_EC"
