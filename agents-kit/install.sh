#!/usr/bin/env bash
# Installs the agent workflow (Sonnet main session, Haiku search/grep/audit, Opus advisor).
#
#   ./install.sh --user                  -> ~/.claude (all your projects)
#   ./install.sh /path/to/repo           -> that repo's .claude/ (shared with the team via git)
#   ./install.sh /path/to/repo --test "pnpm test" --install "pnpm install --frozen-lockfile" --check "pnpm typecheck"
#
# Self-contained: download this single file and run it with bash.
#   ./install.sh --dump DIR              -> only write the template files to DIR (for manual install)
#
# Never overwrites: existing agent files with the same name are skipped (use --force to replace),
# CLAUDE.md gets a section appended once, settings.json is merged (existing keys win, except
# permissions.allow, which is extended).
# Re-run with bash if started with sh/dash.
if [ -z "${BASH_VERSION:-}" ]; then exec bash "$0" "$@"; fi
set -euo pipefail

MODE="" DUMP="" TARGET="" FORCE=0 INSTALL="" TEST="" CHECK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --user) MODE=user; shift ;;
    --dump) MODE=dump; DUMP="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --install) INSTALL="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --check) CHECK="$2"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) MODE=project; TARGET="$1"; shift ;;
  esac
done
[ -n "$MODE" ] || { sed -n '2,15p' "$0"; exit 1; }

# ---- templates ----
tpl_agent_search() {
cat <<'__TPL__'
---
name: search
description: Maps the repository layout, modules, entry points and conventions. Use for any "where is / how is this organized" question. Read-only.
model: claude-haiku-5-5
tools: Read, Glob, Grep
---
You map the repository for the main session. Read excerpts, not whole files.
Return a compact map: relevant paths, one line on each one's role, and entry points.
Never edit files. Report conclusions, not file dumps.
__TPL__
}

tpl_agent_grep() {
cat <<'__TPL__'
---
name: grep
description: Finds every call site, reference and usage of a given symbol, string or API. Runs in its own context.
model: claude-haiku-5-5
tools: Grep, Glob, Read
---
Find all call sites for the symbol or pattern you are given. Search for variants too (aliases, re-exports, dynamic access).
Return a list of `path:line`, each with a one-line snippet, and the total count. Never edit files.
__TPL__
}

tpl_agent_audit() {
cat <<'__TPL__'
---
name: audit
description: Checks a committed diff for correctness, regressions and missing tests, and runs the real install, test and typecheck commands. Runs in a throwaway worktree so it never touches the working branch. Pass it the branch or commit to check.
model: claude-haiku-5-5
tools: Read, Grep, Glob, Bash
isolation: worktree
---
You run in a temporary worktree. It may start from the default branch, not the caller's branch, and it only sees committed changes.
1. If the prompt names a branch or commit, run `git checkout --detach <ref>`.
2. Review `git diff <base>...HEAD` (base = the default branch unless the prompt says otherwise): correctness bugs, edge cases, missing tests.
3. Run the install, test and typecheck commands. Use the ones in the project's CLAUDE.md under "Commands" if present.
   Otherwise detect them: package.json scripts (npm/pnpm/yarn by lockfile), pyproject.toml/pytest, go.mod (`go test ./...`), Cargo.toml (`cargo test`), Makefile targets.
   Run each command on its own: no `&&`, `;`, pipes, `$?` or redirections. Compound commands need approval and will be denied.
4. Report their real output. Never predict results you did not run. If a command is denied, say so.
Report: pass/fail per command with counts, then findings as `path:line` with a one-line reason and a severity (high, medium, low).
Never edit files, commit or push. Write nothing outside the worktree.
__TPL__
}

tpl_agent_advisor() {
cat <<'__TPL__'
---
name: advisor
description: Senior reviewer. Call once, after audit, with the full diff text and the audit report pasted into the prompt. Has no shell, so it cannot produce the diff itself.
model: claude-opus-5-5
tools: Read, Grep, Glob
---
You get a diff and an audit report in the prompt. Read surrounding code with Read/Grep when you need context.
Judge design, security, risk and anything audit missed. Separate what this diff introduces from what was already there.
Reply with a verdict: ship / ship with changes / don't ship. Then list the specific changes as `path:line` with a one-line reason, highest priority first.
Never edit files.
__TPL__
}

tpl_claude_agents() {
cat <<'__TPL__'

## Agent workflow

Main session: Sonnet 5.5. Subagents: `search`, `grep`, `audit` (Haiku 5.5) and `advisor` (Opus 5.5).

- Delegate repo searches to `search` (layout) or `grep` (call sites), and every test run to `audit`. Keep the main context small: work from their summaries, not raw file dumps.
- Before sign-off, in this order:
  1. Commit the change. `audit` runs in a separate worktree and only sees commits.
  2. Call `audit` with the branch or commit to check.
  3. Call `advisor` with the diff text (`git diff <base>...HEAD`) and the audit report pasted into the prompt.
  4. Apply what advisor asks for, commit, and run `audit` again.
- Subagents cannot call other subagents.
__TPL__
}

tpl_claude_commands() {
cat <<'__TPL__'

## Commands
- Install: `__INSTALL__`
- Test: `__TEST__`
- Typecheck/lint: `__CHECK__`
__TPL__
}

tpl_flow_script() {
cat <<'__TPL__'
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
__TPL__
}

AGENTS="search grep audit advisor"

if [ "$MODE" = dump ]; then
  mkdir -p "$DUMP/.claude/agents" "$DUMP/scripts"
  for a in $AGENTS; do "tpl_agent_$a" > "$DUMP/.claude/agents/$a.md"; done
  tpl_claude_agents > "$DUMP/CLAUDE.agents.md"
  tpl_claude_commands > "$DUMP/CLAUDE.commands.md"
  tpl_flow_script > "$DUMP/scripts/claude-flow.sh"
  echo "Templates written to $DUMP"; exit 0
fi

command -v python3 >/dev/null || { echo "python3 is required to merge settings.json" >&2; exit 1; }

if [ "$MODE" = user ]; then
  CLAUDE_DIR="$HOME/.claude"; MEMORY="$CLAUDE_DIR/CLAUDE.md"
else
  [ -d "$TARGET/.git" ] || { echo "$TARGET is not a git repo (audit needs git worktrees)" >&2; exit 1; }
  TARGET="$(cd "$TARGET" && pwd)"; CLAUDE_DIR="$TARGET/.claude"; MEMORY="$TARGET/CLAUDE.md"
  # Detect commands when not given.
  if [ -z "$TEST" ]; then
    if   [ -f "$TARGET/pnpm-lock.yaml" ]; then INSTALL=${INSTALL:-"pnpm install --frozen-lockfile"}; TEST="pnpm test"; CHECK=${CHECK:-"pnpm run typecheck"}
    elif [ -f "$TARGET/yarn.lock" ]; then INSTALL=${INSTALL:-"yarn install --frozen-lockfile"}; TEST="yarn test"; CHECK=${CHECK:-"yarn typecheck"}
    elif [ -f "$TARGET/package.json" ]; then INSTALL=${INSTALL:-"npm ci"}; TEST="npm test"; CHECK=${CHECK:-"npm run typecheck"}
    elif [ -f "$TARGET/pyproject.toml" ] || [ -f "$TARGET/pytest.ini" ]; then INSTALL=${INSTALL:-"pip install -e ."}; TEST="pytest"; CHECK=${CHECK:-"ruff check ."}
    elif [ -f "$TARGET/go.mod" ]; then INSTALL=${INSTALL:-"go mod download"}; TEST="go test ./..."; CHECK=${CHECK:-"go vet ./..."}
    elif [ -f "$TARGET/Cargo.toml" ]; then INSTALL=${INSTALL:-"cargo fetch"}; TEST="cargo test"; CHECK=${CHECK:-"cargo clippy"}
    fi
  fi
fi

mkdir -p "$CLAUDE_DIR/agents"

# 1. Agents
for a in $AGENTS; do
  dest="$CLAUDE_DIR/agents/$a.md"
  if [ -e "$dest" ] && [ "$FORCE" = 0 ]; then
    echo "skip   $dest (exists; use --force to replace)"
  else
    "tpl_agent_$a" > "$dest"; echo "agent  $dest"
  fi
done

# 2. CLAUDE.md section (once)
touch "$MEMORY"
if grep -q "^## Agent workflow" "$MEMORY"; then
  echo "skip   $MEMORY (already has '## Agent workflow')"
else
  tpl_claude_agents >> "$MEMORY"; echo "memory $MEMORY"
  if [ "$MODE" = project ]; then
    if [ -n "$TEST" ]; then
      sed -e "s|__INSTALL__|${INSTALL:-n/a}|" -e "s|__TEST__|$TEST|" -e "s|__CHECK__|${CHECK:-n/a}|" >> "$MEMORY" < <(tpl_claude_commands)
    else
      echo "warn   no test command detected: add a '## Commands' section to $MEMORY or rerun with --test"
    fi
  fi
fi

# 3. settings.json (merge)
python3 - "$CLAUDE_DIR/settings.json" "$MODE" "$INSTALL" "$TEST" "$CHECK" <<'PY'
import json, os, sys
path, mode, *cmds = sys.argv[1:]
data = {}
if os.path.exists(path):
    with open(path) as f:
        data = json.load(f)
data.setdefault("model", "claude-sonnet-5-5")
allow = data.setdefault("permissions", {}).setdefault("allow", [])
wanted = ["Bash(git status)", "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)", "Bash(git checkout --detach:*)"]
wanted += [f"Bash({c})" for c in cmds if c and c != "n/a"]
for rule in wanted:
    if rule not in allow:
        allow.append(rule)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"config {path} (model: {data['model']}, {len(allow)} allow rules)")
PY

# 4. Project extras
if [ "$MODE" = project ]; then
  mkdir -p "$TARGET/scripts"
  if [ -e "$TARGET/scripts/claude-flow.sh" ] && [ "$FORCE" = 0 ]; then
    echo "skip   $TARGET/scripts/claude-flow.sh (exists)"
  else
    sed -e "s|__INSTALL__|${INSTALL:-true}|" -e "s|__TEST__|${TEST:-true}|" -e "s|__CHECK__|${CHECK:-true}|" > "$TARGET/scripts/claude-flow.sh" < <(tpl_flow_script)
    chmod +x "$TARGET/scripts/claude-flow.sh"; echo "script $TARGET/scripts/claude-flow.sh"
  fi
  grep -qx ".claude/worktrees/" "$TARGET/.gitignore" 2>/dev/null || { echo ".claude/worktrees/" >> "$TARGET/.gitignore"; echo "ignore $TARGET/.gitignore (+ .claude/worktrees/)"; }
fi

echo "Done. Start a new Claude Code session so it loads the agents (check with /agents)."
