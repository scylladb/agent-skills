#!/bin/bash
# Validates skill directories locally.
#
# This script should be updated together with .github/scripts/validate-skills.sh.
#
# Usage: 
#	- validate-skills.sh  # Validates all skills in the repository
#   - validate-skills.sh [path/to/skill/] # Validates a specific skill directory
# 
#
# Exit codes:
#   0  All validated skills passed (or no skill files were modified).
#   1  One or more skills failed validation.

set -euo pipefail

if ! command -v skill-validator &>/dev/null; then
  echo "Error: skill-validator is not installed."
  echo "Installation: \`go install github.com/agent-ecosystem/skill-validator/cmd/skill-validator@latest\`"
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Error: not inside a git repository."
  exit 1
}
cd "$REPO_ROOT"

SKILL_PATH="${1:-skills/}"

# Normalize absolute paths to be relative to the repo root.
if [[ "$SKILL_PATH" == /* ]]; then
  SKILL_PATH="${SKILL_PATH#"$REPO_ROOT"/}"
fi

if [ ! -d "$SKILL_PATH" ]; then
  echo "Error: '$SKILL_PATH' is not a directory."
  exit 1
fi

# Ensure the path ends with a trailing slash for consistency with the validator.
[[ "$SKILL_PATH" != */ ]] && SKILL_PATH="$SKILL_PATH/"

skill-validator check --strict "$SKILL_PATH"
