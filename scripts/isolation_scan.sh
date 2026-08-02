#!/usr/bin/env bash
# Deterministic isolation scan (Themis).
#
# Usage:
#   isolation_scan.sh --mode engine|product --root <repo> [--peer-pattern REGEX] [--base origin/main]
#
# Exit 0 = clean. Exit 1 = findings printed.
set -uo pipefail

MODE="engine"
ROOT=""
PEER=""
BASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    --peer-pattern) PEER="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: isolation_scan.sh --mode engine|product --root <repo> [--peer-pattern REGEX]"
      exit 0
      ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$ROOT" && -d "$ROOT" ]] || { echo "Need --root <existing dir>" >&2; exit 1; }
[[ "$MODE" == "engine" || "$MODE" == "product" ]] || { echo "Need --mode engine|product" >&2; exit 1; }

cd "$ROOT"

# Generic high-risk secrets / host paths (both modes)
SECRET='(api[_-]?key\s*=\s*['\''\"]?[a-zA-Z0-9_-]{20,}|Bearer [a-zA-Z0-9._-]{20,}|xox[baprs]-|ATATT3|ghp_[a-zA-Z0-9]{20,}|-----BEGIN (RSA |OPENSSH )?PRIVATE KEY-----)'
HOSTPATH='(/Users/[A-Za-z0-9._-]+/(Downloads|projects)/|/home/[A-Za-z0-9._-]+/)'

# Engine mode: common multi-tenant leak patterns (extend carefully; false positives OK as suggestions in LLM pass)
ENGINE_LEAK='(\bepic_key:\s*[\"'\'']?[A-Z]+-[0-9]+|/rest/agile/1\.0/board/[0-9]+)'

FAIL=0
scan_regex() {
  local label="$1" pattern="$2"
  local hits
  if [[ -n "$BASE" ]] && git rev-parse --git-dir >/dev/null 2>&1; then
    hits=$(git --no-pager diff -U0 "$BASE"...HEAD 2>/dev/null | grep -E '^\+' | grep -Ev '^\+\+\+' | grep -nE "$pattern" || true)
  else
    hits=$(git grep -nE "$pattern" -- '.cursor' 'scripts' 'templates' 'docs' '*.md' '.github' 2>/dev/null || true)
  fi
  if [[ -n "$hits" ]]; then
    echo "isolation ($label):"
    echo "$hits" | head -40
    FAIL=1
  fi
}

scan_regex "secrets" "$SECRET"
scan_regex "host-paths" "$HOSTPATH"

if [[ "$MODE" == "engine" ]]; then
  scan_regex "engine-epic-hardcode" "$ENGINE_LEAK"
fi

if [[ "$MODE" == "product" && -n "$PEER" ]]; then
  scan_regex "cross-tenant-peer" "$PEER"
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "isolation_scan: OK (mode=$MODE root=$ROOT)"
fi
exit "$FAIL"
