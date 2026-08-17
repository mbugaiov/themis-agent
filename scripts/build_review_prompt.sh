#!/usr/bin/env bash
# Build the headless Themis review prompt: shared review-rules/* + local extras.
#
# Usage:
#   bash scripts/build_review_prompt.sh \
#     --pr 12 \
#     --base origin/main \
#     --label example-agent \
#     [--local-rule .cursor/rules/code-review.mdc] \
#     [--agents AGENTS.md] \
#     [--themis-root .themis-agent]
#
# When reviewing themis-agent itself, pass --themis-root .
#
# Shared rules are inlined from review-rules/[0-9]*.md so adding a new NN-*.md
# on themis main applies on the next consumer review with no engine edits.
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
THEMIS_ROOT="$SCRIPT_ROOT"
PR=""
BASE="origin/main"
LABEL="repository"
LOCAL_RULE=""
AGENTS=""
EXTRA=""
CALLER_PWD="${PWD}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR="${2:-}"; shift 2 ;;
    --base) BASE="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --local-rule) LOCAL_RULE="${2:-}"; shift 2 ;;
    --agents) AGENTS="${2:-}"; shift 2 ;;
    --themis-root) THEMIS_ROOT="${2:-}"; shift 2 ;;
    --extra) EXTRA="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PR" ]]; then
  echo "Usage: build_review_prompt.sh --pr <n> --base <ref> --label <name> ..." >&2
  exit 2
fi

if [[ "$THEMIS_ROOT" != /* ]]; then
  THEMIS_ROOT="$(cd "$CALLER_PWD/$THEMIS_ROOT" && pwd)"
fi
RULES_DIR="$THEMIS_ROOT/review-rules"
if [[ ! -d "$RULES_DIR" ]]; then
  echo "build_review_prompt: missing review-rules at $RULES_DIR" >&2
  exit 2
fi

RULE_FILES=()
while IFS= read -r f; do
  RULE_FILES+=("$f")
done < <(find "$RULES_DIR" -maxdepth 1 -type f -name '[0-9]*.md' | LC_ALL=C sort)

if [[ ${#RULE_FILES[@]} -eq 0 ]]; then
  echo "build_review_prompt: no review-rules/[0-9]*.md under $RULES_DIR" >&2
  exit 2
fi

cat <<EOF
You are Themis, the centralized code-review agent, reviewing GitHub PR #${PR} on ${LABEL}.

## Authority order (highest first)
1. Shared Themis rules inlined below (from themis-agent/review-rules/).
2. Local project rule(s) listed after — product/engine specifics only; must NOT weaken shared rules.
3. AGENTS.md / other local docs when cited.

Review ONLY changes vs ${BASE}. Begin with: git --no-pager diff ${BASE}...HEAD

Isolation / cross-tenant leaks are enforced by the separate CI job isolation (Themis); still fold obvious leak findings into Blocking issues if you see them.

Produce exactly the output sections required by the shared output contract.

EOF

echo "## Shared Themis review rules (central pack — auto-loaded)"
echo
for f in "${RULE_FILES[@]}"; do
  echo "### FILE: review-rules/$(basename "$f")"
  echo
  cat "$f"
  echo
  echo "---"
  echo
done

if [[ -n "$LOCAL_RULE" ]]; then
  echo "## Local project rules (do not weaken shared pack)"
  echo
  if [[ -f "$LOCAL_RULE" ]]; then
    echo "### FILE: $LOCAL_RULE"
    echo
    cat "$LOCAL_RULE"
    echo
  else
    echo "(missing local rule file: $LOCAL_RULE — still enforce shared pack)"
    echo
  fi
fi

if [[ -n "$AGENTS" && -f "$AGENTS" ]]; then
  echo "## Local AGENTS.md (context)"
  echo
  echo "### FILE: $AGENTS (excerpt)"
  echo
  head -n 200 "$AGENTS"
  echo
fi

if [[ -n "$EXTRA" ]]; then
  echo "## Extra instructions"
  echo
  echo "$EXTRA"
  echo
fi
