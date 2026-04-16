#!/bin/bash
# Validates skills that were modified in the current PR.
# Unmodified skills are ignored.
#
# This script should be updated together with tests/validate-skills.sh.
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

# Diff against the PR base branch, fall back to main.
BASE_BRANCH="${GITHUB_BASE_REF:-main}"

# Find all skill directories that contain modified files.
changed_skills=$(
  git diff --name-only "origin/${BASE_BRANCH}...HEAD" \
  | grep '^skills/' \
  | sed 's|^\(skills/[^/]*\)/.*|\1|' \
  | sort -u
)

if [ -z "$changed_skills" ]; then
  echo "No skill files were modified. Skipping validation."
  exit 0
fi

exit_code=0
while IFS= read -r skill_dir; do
  if [ ! -d "$skill_dir" ]; then
    echo "Warning: '$skill_dir' no longer exists, skipping."
    continue
  fi
  echo "Validating $skill_dir ..."
  if ! skill-validator check --strict --emit-annotations -o markdown "${skill_dir}/"; then
    exit_code=1
  fi
done <<< "$changed_skills"

exit "$exit_code"
