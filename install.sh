#!/usr/bin/env bash
# install.sh — set up a Mac for the scrubs Claude Code workbench.
#
# Installs (skipping anything already present):
#   Homebrew, git, AWS CLI, uv, iTerm2, VS Code, Claude Code,
#   Claude Code plugins (sentry, postman, superpowers, comfy-cloud),
#   AWS skills + AWS MCP server for Claude Code (via `aws configure agent-toolkit`),
#   the Claude Code VS Code extension, and the `ws` command.
#
# Usage: ./install.sh [--dry-run]
#
# Safe to re-run. --dry-run prints what would be done without changing anything.

set -euo pipefail

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
ZPROFILE="$HOME/.zprofile"
ZSHRC="$HOME/.zshrc"

# Marketplaces as name=github-repo, plugins as plugin@marketplace.
MARKETPLACES=(
  claude-plugins-official=anthropics/claude-plugins-official
  comfy-skills=Comfy-Org/comfy-skills
)
PLUGINS=(
  sentry@claude-plugins-official
  postman@claude-plugins-official
  superpowers@claude-plugins-official
  comfy-cloud@comfy-skills
)
VSCODE_EXTENSION="anthropic.claude-code"

step() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { echo "    + $*"; [[ -n "$DRY_RUN" ]] || "$@"; }

# Append a line to a shell rc file unless it's already there.
add_line() {
  local file="$1" line="$2"
  if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
    ok "$file already has: $line"
  else
    echo "    + echo '$line' >> $file"
    [[ -n "$DRY_RUN" ]] || printf '\n%s\n' "$line" >> "$file"
  fi
}

[[ "$(uname -s)" == "Darwin" ]] || die "this script is for macOS"
[[ -n "$DRY_RUN" ]] && echo "Dry run: nothing will be changed."

# --- Homebrew --------------------------------------------------------------
step "Homebrew"
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW=/opt/homebrew/bin/brew
elif [[ -x /usr/local/bin/brew ]]; then
  BREW=/usr/local/bin/brew
else
  BREW=""
fi

if [[ -n "$BREW" ]]; then
  ok "installed ($BREW)"
else
  run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ "$(uname -m)" == "arm64" ]]; then BREW=/opt/homebrew/bin/brew; else BREW=/usr/local/bin/brew; fi
fi
add_line "$ZPROFILE" "eval \"\$($BREW shellenv)\""
if [[ -x "$BREW" ]]; then
  eval "$("$BREW" shellenv)"
elif [[ -z "$DRY_RUN" ]]; then
  die "Homebrew install failed"
fi

brew_formula() {
  local formula="$1" cmd="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$formula already installed ($(command -v "$cmd"))"
  else
    run brew install "$formula"
  fi
}

brew_cask() {
  local cask="$1" app="$2"
  if [[ -d "/Applications/$app" || -d "$HOME/Applications/$app" ]]; then
    ok "$app already installed"
  else
    run brew install --cask "$cask"
  fi
}

# --- CLI tools and apps ----------------------------------------------------
step "git, AWS CLI and uv"
brew_formula git git
brew_formula awscli aws
brew_formula uv uvx   # the AWS MCP server runs via uvx

step "iTerm2 and VS Code"
brew_cask iterm2 "iTerm.app"
brew_cask visual-studio-code "Visual Studio Code.app"

# Make the `code` command available even if VS Code was installed by hand.
if ! command -v code >/dev/null 2>&1; then
  VSCODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  if [[ -x "$VSCODE_BIN" ]]; then
    run mkdir -p "$LOCAL_BIN"
    run ln -sf "$VSCODE_BIN" "$LOCAL_BIN/code"
  fi
fi

# --- PATH ------------------------------------------------------------------
step "PATH"
if grep -qs '\.local/bin' "$HOME/.zshenv" "$ZPROFILE" "$ZSHRC"; then
  ok "~/.local/bin already added to PATH in your zsh config"
else
  add_line "$ZSHRC" 'export PATH="$HOME/.local/bin:$PATH"'
fi
export PATH="$LOCAL_BIN:$PATH"

# --- Claude Code -----------------------------------------------------------
step "Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "installed ($(claude --version 2>/dev/null | head -1))"
else
  run bash -c "curl -fsSL https://claude.ai/install.sh | bash"
  command -v claude >/dev/null 2>&1 || [[ -n "$DRY_RUN" ]] || die "Claude Code install failed"
fi

# --- Claude Code plugins ---------------------------------------------------
step "Claude Code plugins"
if [[ -n "$DRY_RUN" ]] && ! command -v claude >/dev/null 2>&1; then
  warn "claude not installed yet; would add marketplaces and install: ${PLUGINS[*]}"
else
  marketplaces="$(claude plugin marketplace list 2>/dev/null || true)"
  for entry in "${MARKETPLACES[@]}"; do
    name="${entry%%=*}" repo="${entry#*=}"
    if grep -qw "$name" <<<"$marketplaces"; then
      ok "marketplace $name already added"
    else
      run claude plugin marketplace add "$repo" || warn "could not add marketplace $name"
    fi
  done

  installed="$(claude plugin list 2>/dev/null || true)"
  for plugin in "${PLUGINS[@]}"; do
    if grep -qF "$plugin" <<<"$installed"; then
      ok "$plugin already installed"
    else
      run claude plugin install "$plugin" --scope user || warn "could not install $plugin"
    fi
  done
fi

# --- AWS skills + MCP server for Claude Code --------------------------------
step "AWS skills and MCP server for Claude Code"
if grep -qs '"aws-mcp"' "$HOME/.claude.json"; then
  ok "AWS MCP server already configured"
else
  # agent-toolkit only sets up agents whose config directory exists.
  run mkdir -p "$HOME/.claude"
  run aws configure agent-toolkit --yes || warn "aws configure agent-toolkit failed; re-run it by hand"
fi

# --- VS Code extension -----------------------------------------------------
step "Claude Code VS Code extension"
if ! command -v code >/dev/null 2>&1; then
  if [[ -n "$DRY_RUN" ]]; then
    echo "    + code --install-extension $VSCODE_EXTENSION"
  else
    warn "'code' command not found; open VS Code and install the Claude Code extension by hand"
  fi
elif code --list-extensions 2>/dev/null | grep -qix "$VSCODE_EXTENSION"; then
  ok "$VSCODE_EXTENSION already installed"
else
  run code --install-extension "$VSCODE_EXTENSION"
fi

# --- ws --------------------------------------------------------------------
step "ws command"
if [[ "$(readlink "$LOCAL_BIN/ws" 2>/dev/null)" == "$SCRIPT_DIR/ws" ]]; then
  ok "$LOCAL_BIN/ws already links to $SCRIPT_DIR/ws"
else
  run mkdir -p "$LOCAL_BIN"
  run chmod +x "$SCRIPT_DIR/ws"
  run ln -sf "$SCRIPT_DIR/ws" "$LOCAL_BIN/ws"
fi

# --- Done ------------------------------------------------------------------
step "Done"
cat <<'EOF'
    Next steps:
      1. Open a new terminal (or run: source ~/.zprofile ~/.zshrc)
      2. Sign in to Claude Code:   claude   (then follow the login prompt)
      3. Sign in to AWS:           aws login   (or: aws configure sso)
      4. Sign in to Sentry and Postman the first time Claude uses them (run /mcp in Claude Code)
      5. Start a workspace:        ws my-feature
EOF
