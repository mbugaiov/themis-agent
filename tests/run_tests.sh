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

echo
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
