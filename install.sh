#!/usr/bin/env bash
# install.sh — set up a Mac for the scrubs Claude Code workbench.
#
# Installs (skipping anything already present):
#   Homebrew, git, GitHub CLI, AWS CLI, uv, Maven, Java 11/21/25 (Temurin),
#   Oh My Zsh (auto-updating), iTerm2, VS Code, Sublime Text (+ MarkdownPreview), Claude Code,
#   Claude Code plugins (sentry, postman, superpowers, comfy-cloud),
#   AWS skills + AWS MCP server for Claude Code (via `aws configure agent-toolkit`),
#   the Claude Code VS Code extension, and the `repomancer` command.
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

# run_remote <shell> <url> [VAR=value ...] — download an installer script and
# run it, printing the URL rather than the whole script.
run_remote() {
  local shell="$1" url="$2" script status; shift 2
  echo "    + ${*:+$* }$shell <(curl -fsSL $url)"
  [[ -n "$DRY_RUN" ]] && return 0
  script="$(mktemp)"
  curl -fsSL "$url" -o "$script" || { rm -f "$script"; return 1; }
  status=0
  env "$@" "$shell" "$script" || status=$?
  rm -f "$script"
  return "$status"
}

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

# --- Network check ---------------------------------------------------------
# Fail early and clearly if a download host is blocked, rather than halfway
# through Homebrew. Any HTTP answer counts; only "can't connect" fails.
step "Network"
NEEDED_HOSTS=(github.com raw.githubusercontent.com ghcr.io formulae.brew.sh claude.ai packagecontrol.io)
unreachable=() intercepted=()
for host in "${NEEDED_HOSTS[@]}"; do
  code=0
  curl -sS -o /dev/null --max-time 15 "https://$host" 2>/dev/null || code=$?
  case "$code" in
    0)     ok "$host" ;;
    35|60) intercepted+=("$host"); warn "$host: certificate not trusted (traffic is being intercepted)" ;;
    6)     unreachable+=("$host"); warn "$host: name can't be resolved (blocked or no DNS)" ;;
    *)     unreachable+=("$host"); warn "$host: can't connect (curl error $code)" ;;
  esac
done
if (( ${#intercepted[@]} )); then
  printf '\n    Something on this network replaces the certificates of: %s\n' "${intercepted[*]}" >&2
  printf '    That is usually company security software (Cisco Umbrella, Zscaler, ...)\n' >&2
  printf '    inspecting HTTPS traffic. Command-line tools reject those certificates.\n' >&2
  printf '    Ask IT to exclude these hosts from SSL inspection, then re-run this installer.\n' >&2
fi
if (( ${#unreachable[@]} )); then
  printf '\n    This Mac can'\''t reach: %s\n' "${unreachable[*]}" >&2
  printf '    Usually a VPN, a filtering network (company security software such as\n' >&2
  printf '    Cisco Umbrella or Zscaler, Pi-hole) or an unfinished Wi-Fi login.\n' >&2
  printf '    Check with:   nslookup %s\n' "${unreachable[0]}" >&2
  printf '    Ask IT to allow these hosts, or try another network, then re-run this\n' >&2
  printf '    installer. It picks up where it left off.\n' >&2
fi
# Steps that are already done don't need these hosts, so a set-up Mac can go on.
if (( ${#intercepted[@]} + ${#unreachable[@]} )) && [[ -z "$DRY_RUN" ]]; then
  echo
  confirm "Continue anyway? Downloads from those hosts will fail." N || exit 1
fi

# When run from a checkout, use it; when piped from curl, BASH_SOURCE is empty
# or points at bash itself, so we clone the repo later instead.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$dir/repomancer" ]] && SCRIPT_DIR="$dir"
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
  run_remote /bin/bash https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    || die "Homebrew install failed (see its output above). Fix what it reports, then re-run this installer."
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

step "iTerm2, VS Code and Sublime Text"
brew_cask iterm2 "iTerm.app"
brew_cask visual-studio-code "Visual Studio Code.app"
brew_cask sublime-text "Sublime Text.app"

# The casks put `code` and `subl` on PATH; apps installed by hand don't, so
# link their command-line tools into ~/.local/bin.
link_app_cli() {
  local cmd="$1" bin="$2"
  if [[ "$(readlink "$LOCAL_BIN/$cmd" 2>/dev/null)" == "$bin" ]]; then
    ok "$cmd command available ($LOCAL_BIN/$cmd)"
  elif command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd command available ($(command -v "$cmd"))"
  elif [[ -x "$bin" ]]; then
    run mkdir -p "$LOCAL_BIN"
    run ln -sf "$bin" "$LOCAL_BIN/$cmd"
  elif [[ -n "$DRY_RUN" ]]; then
    echo "    + (link $cmd once the app is installed)"
  else
    warn "$cmd command not found and $bin is missing"
  fi
}
link_app_cli code "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
link_app_cli subl "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl"

# --- Oh My Zsh -------------------------------------------------------------
step "Oh My Zsh"
OMZ_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [[ -d "$OMZ_DIR" ]]; then
  ok "installed ($OMZ_DIR)"
else
  # RUNZSH/CHSH: don't switch shells mid-install. KEEP_ZSHRC: never replace an
  # existing ~/.zshrc (without one, Oh My Zsh writes its own template).
  run_remote sh https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes || warn "Oh My Zsh install failed"
  [[ -f "$ZSHRC" ]] && grep -q 'oh-my-zsh.sh' "$ZSHRC" && SHELL_CHANGED=1
fi

# An existing ~/.zshrc that Oh My Zsh kept doesn't load it yet; put the loader
# at the top so your own settings further down still win.
if [[ -d "$OMZ_DIR" || -n "$DRY_RUN" ]] && ! grep -qs 'oh-my-zsh.sh' "$ZSHRC"; then
  echo "    + add Oh My Zsh loader to the top of $ZSHRC"
  SHELL_CHANGED=1
  if [[ -z "$DRY_RUN" ]]; then
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
# >>> oh-my-zsh >>>
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
zstyle ':omz:update' mode auto
plugins=(git)
source $ZSH/oh-my-zsh.sh
# <<< oh-my-zsh <<<

EOF
    [[ -f "$ZSHRC" ]] && cat "$ZSHRC" >> "$tmp"
    cat "$tmp" > "$ZSHRC" && rm -f "$tmp"
  fi
fi

# Update automatically instead of asking at terminal start. An update mode
# you've set yourself (an uncommented zstyle line) is left alone.
OMZ_AUTO="zstyle ':omz:update' mode auto"
if grep -qsE "^[[:space:]]*zstyle ':omz:update' mode" "$ZSHRC"; then
  ok "update mode: $(grep -E "^[[:space:]]*zstyle ':omz:update' mode" "$ZSHRC" | head -1 | awk '{print $4}')"
elif [[ -f "$ZSHRC" ]] && grep -qsE "^# *$OMZ_AUTO" "$ZSHRC"; then
  echo "    + enable automatic updates in $ZSHRC"
  SHELL_CHANGED=1
  [[ -n "$DRY_RUN" ]] || sed -i '' -E "s/^# *($OMZ_AUTO)/\1/" "$ZSHRC"
elif grep -qs 'oh-my-zsh.sh' "$ZSHRC"; then
  echo "    + enable automatic updates in $ZSHRC"
  SHELL_CHANGED=1
  # The zstyle has to come before Oh My Zsh is loaded.
  [[ -n "$DRY_RUN" ]] || sed -i '' -E "/^[[:space:]]*source .*oh-my-zsh\.sh/i\\
$OMZ_AUTO
" "$ZSHRC"
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
can_clone_scrubs() { GIT_TERMINAL_PROMPT=0 git ls-remote "$SCRUBS_REPO" HEAD >/dev/null 2>&1; }

# If git can already clone scrubs, leave its credentials alone. Otherwise let
# git use gh for HTTPS credentials, unless GITHUB_TOKEN/GH_TOKEN is set: gh
# would hand that token to git instead of your login, and such tokens often
# can't read repos.
if [[ -n "$DRY_RUN" ]]; then
  echo "    + (if git can't clone SmartScrubs/scrubs yet) gh auth setup-git --hostname github.com"
elif can_clone_scrubs; then
  ok "git can access SmartScrubs/scrubs"
elif [[ -n "${GITHUB_TOKEN:-}${GH_TOKEN:-}" ]]; then
  warn "git can't access SmartScrubs/scrubs. GITHUB_TOKEN/GH_TOKEN is set in your environment;"
  warn "remove it (or give it 'repo' scope), then re-run this installer"
elif command -v gh >/dev/null 2>&1 && gh auth status --hostname github.com >/dev/null 2>&1; then
  run gh auth setup-git --hostname github.com
  if can_clone_scrubs; then
    ok "git can access SmartScrubs/scrubs"
  else
    warn "can't reach SmartScrubs/scrubs; check that your GitHub account is in the SmartScrubs org"
  fi
else
  warn "can't reach SmartScrubs/scrubs; sign in with 'gh auth login' and re-run this installer"
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
  run_remote bash https://claude.ai/install.sh
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

# --- Sublime Text packages -------------------------------------------------
step "Sublime Text Markdown preview"
ST_DIR="$HOME/Library/Application Support/Sublime Text"
PC_PACKAGE="$ST_DIR/Installed Packages/Package Control.sublime-package"
PC_SETTINGS="$ST_DIR/Packages/User/Package Control.sublime-settings"

if [[ -f "$PC_PACKAGE" ]]; then
  ok "Package Control already installed"
else
  run mkdir -p "$ST_DIR/Installed Packages"
  run curl -fsSL -o "$PC_PACKAGE" "https://packagecontrol.io/Package%20Control.sublime-package" \
    || warn "could not download Package Control"
fi

# Package Control installs anything listed in installed_packages that's
# missing the next time Sublime Text starts.
if grep -qs '"MarkdownPreview"' "$PC_SETTINGS"; then
  ok "MarkdownPreview already listed"
else
  echo "    + add MarkdownPreview to $PC_SETTINGS"
  if [[ -z "$DRY_RUN" ]]; then
    mkdir -p "$(dirname "$PC_SETTINGS")"
    [[ -f "$PC_SETTINGS" ]] && cp "$PC_SETTINGS" "$PC_SETTINGS.bak"
    # Sublime settings allow comments and trailing commas; strict JSON doesn't.
    /usr/bin/python3 - "$PC_SETTINGS" <<'PYEOF' || warn "could not update $PC_SETTINGS; install MarkdownPreview with Package Control: Install Package"
import json, os, re, sys
path = sys.argv[1]
text = open(path).read() if os.path.exists(path) else ""
text = re.sub(r'^\s*//.*$', '', text, flags=re.M)
text = re.sub(r',(\s*[\]}])', r'\1', text)
settings = json.loads(text) if text.strip() else {}
packages = settings.setdefault("installed_packages", [])
for name in ("Package Control", "MarkdownPreview"):
    if name not in packages:
        packages.append(name)
with open(path, "w") as f:
    json.dump(settings, f, indent="\t")
    f.write("\n")
PYEOF
    if pgrep -xq sublime_text; then
      warn "restart Sublime Text so Package Control installs MarkdownPreview"
    fi
  fi
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

# --- repomancer ------------------------------------------------------------
step "repomancer config and workspace folder"
RM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/repomancer/config"
if [[ -f "$RM_CONFIG" ]]; then
  ok "config exists: $RM_CONFIG"
else
  echo "    + create $RM_CONFIG"
  if [[ -z "$DRY_RUN" ]]; then
    mkdir -p "$(dirname "$RM_CONFIG")"
    cat > "$RM_CONFIG" <<'EOF'
# repomancer configuration (shell syntax). Uncomment a line to override the default.
# The REPOMANCER_ROOT / REPOMANCER_REPO environment variables override this file.

# Folder where repomancer creates workspaces (default: ~/Documents/AIProjects)
#REPOMANCER_ROOT="$HOME/Documents/AIProjects"

# Repo repomancer clones (default: https://github.com/SmartScrubs/scrubs.git)
#REPOMANCER_REPO="https://github.com/SmartScrubs/scrubs.git"
EOF
  fi
fi
# Same lookup as repomancer: environment, then config file, then the default.
rm_root="$( (ROOT_ENV="${REPOMANCER_ROOT:-}"; [[ -f "$RM_CONFIG" ]] && source "$RM_CONFIG" >/dev/null 2>&1; r="${ROOT_ENV:-${REPOMANCER_ROOT:-$HOME/Documents/AIProjects}}"; echo "${r/#\~/$HOME}") )"
if [[ -d "$rm_root" ]]; then
  ok "workspace folder exists: $rm_root"
else
  run mkdir -p "$rm_root"
fi

step "repomancer command"
if [[ "$(readlink "$LOCAL_BIN/repomancer" 2>/dev/null)" == "$SCRIPT_DIR/repomancer" ]]; then
  ok "$LOCAL_BIN/repomancer already links to $SCRIPT_DIR/repomancer"
else
  run mkdir -p "$LOCAL_BIN"
  run chmod +x "$SCRIPT_DIR/repomancer"
  run ln -sf "$SCRIPT_DIR/repomancer" "$LOCAL_BIN/repomancer"
fi
# repomancer used to be called ws; remove the old link once it no longer works.
if [[ -L "$LOCAL_BIN/ws" && ! -e "$LOCAL_BIN/ws" && "$(readlink "$LOCAL_BIN/ws")" == */ws ]]; then
  run rm "$LOCAL_BIN/ws"
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
      2. Start a workspace:        repomancer my-feature

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
