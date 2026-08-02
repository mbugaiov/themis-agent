#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${1:-review.md}"
exec python3 "$ROOT/scripts/review_gate.py" "$FILE"
