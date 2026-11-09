#!/usr/bin/env bash
# Runs Claude Code headless (claude -p) with the agent workflow.
# Headless runs did not apply the allow rules from .claude/settings.json in testing,
# so the same permissions are passed here on the command line, for this run only.
#
# Usage: scripts/claude-flow.sh "task description"
#        CLAUDE_FLOW_COMMIT=1 scripts/claude-flow.sh "..."   # also allow git add / git commit
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Usage: $0 \"task\"" >&2
  exit 1
fi

allowed=(
  "Bash(git status)" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git show:*)"
  "Bash(git checkout --detach:*)"
  "Bash(__INSTALL__)" "Bash(__TEST__)" "Bash(__CHECK__)"
)
if [ "${CLAUDE_FLOW_COMMIT:-0}" = "1" ]; then
  allowed+=("Bash(git add:*)" "Bash(git commit:*)")
fi

exec claude -p "$*" --permission-mode acceptEdits --allowedTools "${allowed[@]}" < /dev/null
