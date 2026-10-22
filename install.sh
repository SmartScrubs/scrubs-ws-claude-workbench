#!/usr/bin/env bash
# install.sh — set up a Mac for the scrubs Claude Code workbench.
#
# Installs (skipping anything already present):
#   Homebrew, git, GitHub CLI, AWS CLI, uv, Maven, Java 11/21/25 (Temurin),
#   iTerm2, VS Code, Claude Code,
#   Claude Code plugins (sentry, postman, superpowers, comfy-cloud),
#   AWS skills + AWS MCP server for Claude Code (via `aws configure agent-toolkit`),
#   the Claude Code VS Code extension, and the `ws` command.
#
# Then walks you through credentials: git name/email, GitHub sign-in,
# AWS sign-in and Claude Code sign-in.
#
# Usage: ./install.sh [--dry-run] [--yes]
#   --dry-run   print what would be done without changing anything
#   --yes       don't ask questions; skip the credential setup
#
# Can also run straight from GitHub, in which case it clones the workbench
# repo into $WORKBENCH_DIR (default: ~/tools/scrubs-ws-claude-workbench).
#
# Safe to re-run.

set -euo pipefail

DRY_RUN=""
ASSUME_YES=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

WORKBENCH_REPO="https://github.com/SmartScrubs/scrubs-ws-claude-workbench.git"
WORKBENCH_DIR="${WORKBENCH_DIR:-$HOME/tools/scrubs-ws-claude-workbench}"
SCRUBS_REPO="https://github.com/SmartScrubs/scrubs.git"
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
JAVA_VERSIONS=(11 21 25)
JAVA_DEFAULT="${JAVA_DEFAULT:-25}"

step() { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
run()  { echo "    + $*"; [[ -n "$DRY_RUN" ]] || "$@"; }

# Questions read from the terminal directly, so they still work when this
# script itself arrives on stdin (curl ... | bash).
INTERACTIVE=""
if [[ -z "$ASSUME_YES" && -z "$DRY_RUN" ]] && { : </dev/tty; } 2>/dev/null; then
  INTERACTIVE=1
fi

# confirm "Question?" [Y|N] — default answer when you just press Enter.
confirm() {
  local default="${2:-Y}" hint reply
  [[ -n "$INTERACTIVE" ]] || return 1
  [[ "$default" == "Y" ]] && hint="[Y/n]" || hint="[y/N]"
  read -r -p "    $1 $hint " reply </dev/tty || return 1
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

# ask "Prompt" [default] — prints the answer.
ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n "$default" ]]; then prompt="$prompt [$default]"; fi
  read -r -p "    $prompt: " reply </dev/tty || true
  echo "${reply:-$default}"
}

# Set when we edit ~/.zprofile or ~/.zshrc, so we know the current shell is stale.
SHELL_CHANGED=""

# Append a block between marker comments to a file unless the marker is there.
add_block() {
  local file="$1" marker="$2" body="$3"
  if [[ -f "$file" ]] && grep -qF ">>> $marker >>>" "$file"; then
    ok "$file already has the $marker block"
  else
    echo "    + add $marker block to $file"
    SHELL_CHANGED=1
    [[ -n "$DRY_RUN" ]] || printf '\n# >>> %s >>>\n%s\n# <<< %s <<<\n' "$marker" "$body" "$marker" >> "$file"
  fi
}

# Append a line to a shell rc file unless it's already there.
add_line() {
  local file="$1" line="$2"
  if [[ -f "$file" ]] && grep -qxF "$line" "$file"; then
    ok "$file already has: $line"
  else
    echo "    + echo '$line' >> $file"
    SHELL_CHANGED=1
    [[ -n "$DRY_RUN" ]] || printf '\n%s\n' "$line" >> "$file"
  fi
}

[[ "$(uname -s)" == "Darwin" ]] || die "this script is for macOS"
[[ -n "$DRY_RUN" ]] && echo "Dry run: nothing will be changed."
[[ -n "$ASSUME_YES" ]] && echo "Running with --yes: skipping credential setup."

# When run from a checkout, use it; when piped from curl, BASH_SOURCE is empty
# or points at bash itself, so we clone the repo later instead.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$dir/ws" ]] && SCRIPT_DIR="$dir"
fi

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
step "git, GitHub CLI, AWS CLI and uv"
brew_formula git git
brew_formula gh gh
brew_formula awscli aws
brew_formula uv uvx   # the AWS MCP server runs via uvx

step "Maven and Java"
brew_formula maven mvn
for v in "${JAVA_VERSIONS[@]}"; do
  if home="$(/usr/libexec/java_home -F -v "$v" 2>/dev/null)"; then
    ok "Java $v already installed ($home)"
  else
    run brew install --cask "temurin@$v"
  fi
done

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

# JAVA_HOME picks the default JDK; `jdk 11` switches the current shell.
add_block "$ZSHRC" "scrubs workbench java" "export JAVA_HOME=\"\$(/usr/libexec/java_home -v $JAVA_DEFAULT 2>/dev/null)\"
jdk() { export JAVA_HOME=\"\$(/usr/libexec/java_home -v \"\$1\")\" && java -version; }"

# --- git identity ----------------------------------------------------------
step "git name and email"
git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"
if [[ -n "$git_name" && -n "$git_email" ]] && ! confirm "Commits are signed as \"$git_name <$git_email>\". Change it?" N; then
  ok "using $git_name <$git_email>"
elif [[ -n "$INTERACTIVE" ]]; then
  git_name="$(ask "Your full name" "$git_name")"
  git_email="$(ask "Your work email" "$git_email")"
  [[ -n "$git_name" ]] && run git config --global user.name "$git_name"
  [[ -n "$git_email" ]] && run git config --global user.email "$git_email"
else
  warn "git name/email not set; run: git config --global user.name \"…\" && git config --global user.email \"…\""
fi

# --- GitHub ----------------------------------------------------------------
step "GitHub sign-in"
if [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
  warn "GITHUB_TOKEN/GH_TOKEN is set in your environment and overrides 'gh auth login'"
fi
if ! command -v gh >/dev/null 2>&1; then
  [[ -n "$DRY_RUN" ]] && echo "    + gh auth login --hostname github.com --git-protocol https --web"
elif gh auth status --hostname github.com >/dev/null 2>&1; then
  ok "signed in to GitHub as $(gh api user --jq .login 2>/dev/null || echo '?')"
elif confirm "Sign in to GitHub now? (opens your browser)"; then
  run gh auth login --hostname github.com --git-protocol https --web || warn "GitHub sign-in failed; run: gh auth login"
else
  warn "not signed in to GitHub; run: gh auth login"
fi
# Let git use gh for HTTPS credentials, so cloning private repos just works.
if command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
  run gh auth setup-git --hostname github.com
fi

if [[ -z "$DRY_RUN" ]]; then
  if GIT_TERMINAL_PROMPT=0 git ls-remote "$SCRUBS_REPO" HEAD >/dev/null 2>&1; then
    ok "you have access to SmartScrubs/scrubs"
  else
    warn "can't reach SmartScrubs/scrubs; check your GitHub sign-in and that you're in the SmartScrubs org"
  fi
fi

# --- AWS -------------------------------------------------------------------
step "AWS sign-in"
if ! command -v aws >/dev/null 2>&1; then
  [[ -n "$DRY_RUN" ]] && echo "    + (would ask how to sign in to AWS)"
elif identity="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)"; then
  ok "signed in to AWS as $identity"
elif [[ -n "$INTERACTIVE" ]]; then
  echo "    How do you want to sign in to AWS?"
  echo "      1) Browser sign-in with your AWS console login (aws login)  [recommended]"
  echo "      2) AWS IAM Identity Center / SSO (aws configure sso)"
  echo "      3) Access key and secret (aws configure)"
  echo "      4) Skip for now"
  case "$(ask "Choose 1-4" 1)" in
    1) run aws login || warn "aws login failed; run it again later" ;;
    2) run aws configure sso || warn "aws configure sso failed; run it again later" ;;
    3) run aws configure || warn "aws configure failed; run it again later" ;;
    *) warn "skipped; run 'aws login' later" ;;
  esac
  identity="$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)" \
    && ok "signed in to AWS as $identity" \
    || warn "AWS credentials still not working. If you used SSO, set AWS_PROFILE to the profile you created"
else
  warn "not signed in to AWS; run: aws login"
fi

# --- Workbench repo --------------------------------------------------------
step "Workbench repo"
if [[ -n "$SCRIPT_DIR" ]]; then
  ok "using this checkout: $SCRIPT_DIR"
elif [[ -d "$WORKBENCH_DIR/.git" ]]; then
  ok "already cloned at $WORKBENCH_DIR"
  run git -C "$WORKBENCH_DIR" pull --ff-only || warn "could not update $WORKBENCH_DIR"
  SCRIPT_DIR="$WORKBENCH_DIR"
else
  run mkdir -p "$(dirname "$WORKBENCH_DIR")"
  run git clone "$WORKBENCH_REPO" "$WORKBENCH_DIR" \
    || die "could not clone $WORKBENCH_REPO; sign in with 'gh auth login' and re-run"
  SCRIPT_DIR="$WORKBENCH_DIR"
fi

# --- Claude Code -----------------------------------------------------------
step "Claude Code"
if command -v claude >/dev/null 2>&1; then
  ok "installed ($(claude --version 2>/dev/null | head -1))"
else
  run bash -c "curl -fsSL https://claude.ai/install.sh | bash"
  command -v claude >/dev/null 2>&1 || [[ -n "$DRY_RUN" ]] || die "Claude Code install failed"
fi

if ! command -v claude >/dev/null 2>&1; then
  [[ -n "$DRY_RUN" ]] && echo "    + claude auth login"
elif claude auth status >/dev/null 2>&1; then
  ok "signed in to Claude Code"
elif confirm "Sign in to Claude Code now? (opens your browser)"; then
  run claude auth login || warn "Claude sign-in failed; run: claude auth login"
else
  warn "not signed in to Claude Code; run: claude auth login"
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

# --- MCP server status -----------------------------------------------------
step "MCP servers"
NEEDS_MCP_AUTH=""
if [[ -n "$DRY_RUN" ]]; then
  echo "    + claude mcp list"
elif ! command -v claude >/dev/null 2>&1; then
  warn "claude not installed; skipping"
elif ! claude auth status >/dev/null 2>&1; then
  warn "sign in to Claude Code first (claude auth login), then re-run to check MCP servers"
else
  echo "    Checking MCP servers (this can take a few seconds)…"
  # Lines look like "<name>: <url or command> - <status>".
  while IFS= read -r line; do
    [[ "$line" == *": "*" - "* ]] || continue
    name="${line%%: *}" status="${line##* - }"
    case "$status" in
      *Connected*)              ok "$name" ;;
      *"Needs authentication"*) warn "$name: needs sign-in"; NEEDS_MCP_AUTH=1 ;;
      *)                        warn "$name: ${status:0:80}"; NEEDS_MCP_AUTH=1 ;;
    esac
  done < <(claude mcp list 2>/dev/null || true)
fi

# --- Done ------------------------------------------------------------------
step "Done"
if [[ -n "$NEEDS_MCP_AUTH" ]]; then
  cat <<'EOF'
    Some MCP servers need attention. Run `claude`, type /mcp and pick the server:
      "needs sign-in" → choose Authenticate (signs in through your browser).
      "failed"        → choose Reconnect; if it still fails, it's often temporary.
    You only need the ones you'll actually use.

EOF
fi
cat <<'EOF'
    Next steps:
      1. Sign in to any MCP servers you need (claude → /mcp)
      2. Start a workspace:        ws my-feature

    Anything skipped above can be finished later with:
      gh auth login && gh auth setup-git
      aws login
      claude auth login
EOF

# A script can't change the shell that started it, so if we edited the zsh
# config, hand over to a fresh login shell that has it loaded. Read from the
# terminal so this also works when the script arrived on stdin (curl | bash).
if [[ -n "$SHELL_CHANGED" ]]; then
  if [[ -n "$INTERACTIVE" && "${SHELL:-}" == */zsh ]]; then
    echo
    echo "    Your shell config changed; starting a fresh shell with it loaded…"
    exec "$SHELL" -l </dev/tty
  elif [[ -n "$DRY_RUN" ]]; then
    echo
    echo "    + exec ${SHELL:-zsh} -l   (shell config would change)"
  else
    echo
    echo "    Your shell config changed: open a new terminal (or run: source ~/.zprofile ~/.zshrc)"
  fi
fi
