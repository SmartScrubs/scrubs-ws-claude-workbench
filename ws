#!/usr/bin/env bash
# ws — spin up a fresh clone of the scrubs repo on a new branch and open Claude Code in it.
#
# Usage: ws <branch-name>
#
# Env:
#   WS_ROOT   parent directory for new workspaces (default: current directory)
#   WS_REPO   repo to clone (default: https://github.com/SmartScrubs/scrubs.git)

set -euo pipefail

REPO="${WS_REPO:-https://github.com/SmartScrubs/scrubs.git}"
ROOT="${WS_ROOT:-$PWD}"

die() { echo "ws: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: ws <branch-name>"
BRANCH="$1"

git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die "invalid branch name: $BRANCH"
command -v claude >/dev/null || die "claude CLI not found on PATH"

# Branch names may contain '/', which we don't want as nested directories.
DIR="$ROOT/${BRANCH//\//-}"
[[ -e "$DIR" ]] && die "directory already exists: $DIR"

echo "→ Cloning $REPO into $DIR"
git clone "$REPO" "$DIR"
cd "$DIR"

if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "→ Branch '$BRANCH' already exists on origin, checking it out"
  git switch "$BRANCH"
else
  echo "→ Creating branch '$BRANCH'"
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
