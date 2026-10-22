#!/usr/bin/env bash
# ws — spin up a fresh clone of the scrubs repo on a new branch and open Claude Code in it.
#
# Usage: ws <branch-name> [base-branch]
#
#   base-branch   branch to start from (default: the repo's default branch)
#
# If the workspace folder already exists, ws reopens it instead: it resumes the
# most recent Claude session there, or starts a new one if there isn't one.
#
# Settings, from highest to lowest priority:
#   1. environment variables WS_ROOT / WS_REPO
#   2. the config file ~/.config/ws/config (shell syntax, e.g. WS_ROOT="$HOME/code")
#   3. defaults: WS_ROOT=~/Documents/AIProjects, WS_REPO=https://github.com/SmartScrubs/scrubs.git
#
#   WS_ROOT   parent directory for workspaces
#   WS_REPO   repo to clone

set -euo pipefail

die() { echo "ws: $*" >&2; exit 1; }

ENV_ROOT="${WS_ROOT:-}" ENV_REPO="${WS_REPO:-}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/ws/config"
if [[ -f "$CONFIG" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG" || die "could not read $CONFIG"
fi
ROOT="${ENV_ROOT:-${WS_ROOT:-$HOME/Documents/AIProjects}}"
REPO="${ENV_REPO:-${WS_REPO:-https://github.com/SmartScrubs/scrubs.git}}"
ROOT="${ROOT/#\~/$HOME}"   # allow WS_ROOT=~/... in the config file

[[ $# -ge 1 && $# -le 2 ]] || die "usage: ws <branch-name> [base-branch]"
BRANCH="$1"
BASE="${2:-}"

git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die "invalid branch name: $BRANCH"
command -v claude >/dev/null || die "claude CLI not found on PATH"

# Branch names may contain '/', which we don't want as nested directories.
DIR="$ROOT/${BRANCH//\//-}"

if [[ -e "$DIR" ]]; then
  [[ -e "$DIR/.git" ]] || die "$DIR exists but is not a git repo"
  cd "$DIR"
  echo "→ Reopening existing workspace $DIR (on branch '$(git branch --show-current)')"
  [[ -n "$BASE" ]] && echo "  (ignoring base branch '$BASE')"
  # Claude Code keeps each folder's transcripts in ~/.claude/projects/<path with
  # every non-alphanumeric character replaced by '-'>.
  PROJECT_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(pwd -P | sed 's/[^A-Za-z0-9]/-/g')"
  if compgen -G "$PROJECT_DIR/*.jsonl" >/dev/null; then
    echo "→ Resuming Claude Code session"
    exec claude --continue
  fi
  echo "→ No previous session found, opening Claude Code (session: ws+$BRANCH)"
  exec claude --name "ws+$BRANCH"
fi

mkdir -p "$ROOT"

if [[ -n "$BASE" ]]; then
  git check-ref-format --branch "$BASE" >/dev/null 2>&1 || die "invalid base branch name: $BASE"
  git ls-remote --exit-code --heads "$REPO" "$BASE" >/dev/null 2>&1 \
    || die "base branch '$BASE' not found on $REPO"
fi
echo "→ Cloning $REPO into $DIR"
if [[ -n "$BASE" ]]; then
  git clone --branch "$BASE" "$REPO" "$DIR"
else
  git clone "$REPO" "$DIR"
fi
cd "$DIR"

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "→ Branch '$BRANCH' already exists on origin, checking it out"
  [[ -n "$BASE" ]] && echo "  (ignoring base branch '$BASE')"
  git switch "$BRANCH"
else
  echo "→ Creating branch '$BRANCH' from '$(git branch --show-current)'"
  git switch -c "$BRANCH"
  # Track origin/<branch> so a plain `git push` / `git pull` just works,
  # even though the remote branch doesn't exist yet.
  git config "branch.$BRANCH.remote" origin
  git config "branch.$BRANCH.merge" "refs/heads/$BRANCH"
fi
git config push.autoSetupRemote true
git config push.default current

echo "→ Opening Claude Code (session: ws+$BRANCH)"
exec claude --name "ws+$BRANCH"
