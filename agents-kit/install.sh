#!/usr/bin/env bash
# Installs the agent workflow (Sonnet main session, Haiku search/grep/audit, Opus advisor).
#
#   ./install.sh --user                  -> ~/.claude (all your projects)
#   ./install.sh /path/to/repo           -> that repo's .claude/ (shared with the team via git)
#   ./install.sh /path/to/repo --test "pnpm test" --install "pnpm install --frozen-lockfile" --check "pnpm typecheck"
#
# Never overwrites: existing agent files with the same name are skipped (use --force to replace),
# CLAUDE.md gets a section appended once, settings.json is merged (existing keys win, except
# permissions.allow, which is extended).
set -euo pipefail

KIT="$(cd "$(dirname "$0")" && pwd)/files"
MODE="" TARGET="" FORCE=0 INSTALL="" TEST="" CHECK=""

while [ $# -gt 0 ]; do
  case "$1" in
    --user) MODE=user; shift ;;
    --force) FORCE=1; shift ;;
    --install) INSTALL="$2"; shift 2 ;;
    --test) TEST="$2"; shift 2 ;;
    --check) CHECK="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) MODE=project; TARGET="$1"; shift ;;
  esac
done
[ -n "$MODE" ] || { sed -n '2,12p' "$0"; exit 1; }
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
for f in "$KIT"/.claude/agents/*.md; do
  dest="$CLAUDE_DIR/agents/$(basename "$f")"
  if [ -e "$dest" ] && [ "$FORCE" = 0 ]; then
    echo "skip   $dest (exists; use --force to replace)"
  else
    cp "$f" "$dest"; echo "agent  $dest"
  fi
done

# 2. CLAUDE.md section (once)
touch "$MEMORY"
if grep -q "^## Agent workflow" "$MEMORY"; then
  echo "skip   $MEMORY (already has '## Agent workflow')"
else
  cat "$KIT/CLAUDE.agents.md" >> "$MEMORY"; echo "memory $MEMORY"
  if [ "$MODE" = project ]; then
    if [ -n "$TEST" ]; then
      sed -e "s|__INSTALL__|${INSTALL:-n/a}|" -e "s|__TEST__|$TEST|" -e "s|__CHECK__|${CHECK:-n/a}|" "$KIT/CLAUDE.commands.md" >> "$MEMORY"
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
    sed -e "s|__INSTALL__|${INSTALL:-true}|" -e "s|__TEST__|${TEST:-true}|" -e "s|__CHECK__|${CHECK:-true}|" "$KIT/scripts/claude-flow.sh" > "$TARGET/scripts/claude-flow.sh"
    chmod +x "$TARGET/scripts/claude-flow.sh"; echo "script $TARGET/scripts/claude-flow.sh"
  fi
  grep -qx ".claude/worktrees/" "$TARGET/.gitignore" 2>/dev/null || { echo ".claude/worktrees/" >> "$TARGET/.gitignore"; echo "ignore $TARGET/.gitignore (+ .claude/worktrees/)"; }
fi

echo "Done. Start a new Claude Code session so it loads the agents (check with /agents)."
