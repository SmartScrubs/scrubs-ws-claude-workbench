#!/usr/bin/env bash
# install.sh — set up a Mac for the scrubs Claude Code workbench.
#
# Installs (skipping anything already present):
#   Homebrew, git, GitHub CLI, AWS CLI, uv, fzf, ffmpeg, Maven, Java 11/21/25 (Temurin),
#   Node.js and puppeteer-core (npm, global),
#   the explainer video toolchain (headless Chrome, Kokoro text-to-speech; asks first),
#   Oh My Zsh (auto-updating), iTerm2, VS Code, Sublime Text (+ MarkdownPreview), Claude Code,
#   Claude Code plugins (sentry, postman, superpowers, comfy-cloud),
#   AWS skills + AWS MCP server for Claude Code (via `aws configure agent-toolkit`),
#   the Claude Code VS Code extension, and the `repomancer` and `scry` commands.
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
# The explainer-video skill's toolchain, at the paths and versions its
# template pins (see the "Explainer video toolchain" step).
EXPLAINER_VENV="${EXPLAINER_VENV:-$HOME/.cache/explainer-venv}"
EXPLAINER_CHROME_DIR="${EXPLAINER_CHROME_DIR:-$HOME/.cache/explainer-chrome}"
EXPLAINER_PACKAGES=(
  mlx-audio==0.6.2 "misaki[en]==0.9.4" mlx-whisper==0.4.3 spacy==3.8.17
  "en-core-web-sm @ https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"
)
EXPLAINER_BROWSERS="@puppeteer/browsers@2.6.1"
EXPLAINER_VOICE="mlx-community/Kokoro-82M-bf16"
EXPLAINER_WHISPER="mlx-community/whisper-large-v3-turbo"
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

# --- VPN check -------------------------------------------------------------
# VPNs often block or intercept the downloads below (Homebrew, GitHub,
# claude.ai), and the install then fails halfway in confusing ways. So ask for
# the VPN to be turned off first. ALLOW_VPN=1 skips this.

# Tunnel interfaces with an IPv4 address, as "utun8 10.10.11.246". macOS keeps
# a few utun interfaces for itself, but those only have IPv6 link-local
# addresses.
vpn_tunnels() {
  ifconfig 2>/dev/null | awk '
    /^[a-z]/ { ifc = $1; sub(/:$/, "", ifc) }
    $1 == "inet" && ifc ~ /^(utun|ppp|ipsec|tun|tap|gpd)[0-9]/ && $2 !~ /^169\.254\./ { print ifc " " $2 }'
}

# VPNs that say they're connected: VPNs set up in System Settings, and with
# --tunnels, Cisco's client (macOS's own list reports it as disconnected even
# when it isn't, and asking it takes a couple of seconds).
vpn_connected() {
  local vpn
  if [[ "${1:-}" == --tunnels ]]; then
    for vpn in /opt/cisco/secureclient/bin/vpn /opt/cisco/anyconnect/bin/vpn; do
      if [[ -x "$vpn" ]] && "$vpn" state 2>/dev/null | grep -q 'state: Connected'; then
        echo "Cisco Secure Client"; break
      fi
    done
  fi
  scutil --nc list 2>/dev/null | sed -n 's/^\* (Connected).*"\([^"]*\)".*/\1/p' | sed 's/ *$//'
}

# VPN apps that are running, to name the likely culprit for a tunnel.
vpn_apps() {
  local procs pair
  procs="$(ps -axco command 2>/dev/null)"
  for pair in "PanGPA:GlobalProtect" "FortiClient:FortiClient" "Tunnelblick:Tunnelblick" \
              "openvpn:OpenVPN" "OpenVPN Connect:OpenVPN Connect" "WireGuard:WireGuard" \
              "Tailscale:Tailscale" "ZscalerTunnel:Zscaler" "NordVPN:NordVPN" \
              "ExpressVPN:ExpressVPN" "ProtonVPN:Proton VPN" "Mullvad VPN:Mullvad VPN" \
              "Cisco Secure Client:Cisco Secure Client"; do
    grep -qxF "${pair%%:*}" <<<"$procs" && echo "${pair#*:}"
  done
  return 0
}

step "VPN"
if [[ -n "${ALLOW_VPN:-}" ]]; then
  ok "not checked (ALLOW_VPN is set)"
else
  while true; do
    tunnels="$(vpn_tunnels | paste -sd ',' - | sed 's/,/, /g')"
    connected="$(vpn_connected ${tunnels:+--tunnels} | sort -u | paste -sd ',' - | sed 's/,/, /g')"
    if [[ -z "$tunnels$connected" ]]; then
      ok "no VPN connected"
      break
    fi
    if [[ -n "$connected" ]]; then
      warn "a VPN is connected: $connected${tunnels:+ ($tunnels)}"
    else
      apps="$(vpn_apps | paste -sd ',' - | sed 's/,/, /g')"
      warn "a VPN seems to be connected ($tunnels)${apps:+, probably $apps}"
    fi
    warn "VPNs often block or intercept the downloads this installer needs, so the install fails partway."
    warn "If you have to stay on the VPN, run the installer with ALLOW_VPN=1 in front."
    if [[ -n "$DRY_RUN" ]]; then
      warn "dry run: continuing anyway"
      break
    fi
    [[ -n "$INTERACTIVE" ]] || die "turn off the VPN, then run the installer again"
    read -r -p "    Turn the VPN off, then press Enter to check again (q to quit): " reply </dev/tty || exit 1
    [[ "$reply" != [Qq]* ]] || { echo "    Stopped. Run the installer again once the VPN is off."; exit 1; }
  done
fi

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

# --- Mac and developer tools -----------------------------------------------
step "Mac and developer tools"
APPLE_SILICON=""
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]] && APPLE_SILICON=1
if [[ -n "$APPLE_SILICON" && "$(sysctl -n sysctl.proc_translated 2>/dev/null)" == 1 ]]; then
  die "this terminal runs under Rosetta (Intel emulation). Open one without \"Open using Rosetta\" and re-run."
fi
ok "$([[ -n "$APPLE_SILICON" ]] && echo "Apple Silicon" || echo "Intel") Mac, macOS $(sw_vers -productVersion 2>/dev/null)"

# Apple's git and compilers come from the developer folder xcode-select points
# at. A Mac migrated from an Intel Mac can point at an old Intel-only Xcode,
# and then they fail ("incompatible architecture"). With no developer tools at
# all, the Homebrew installer below installs the Command Line Tools itself.
CLT=/Library/Developer/CommandLineTools
if dev_dir="$(xcode-select -p 2>/dev/null)"; then
  if /usr/bin/git --version >/dev/null 2>&1; then
    ok "developer tools work ($dev_dir)"
  else
    warn "Apple's developer tools in $dev_dir don't work (often an old, Intel-only Xcode)"
    if [[ -n "$DRY_RUN" ]]; then
      echo "    + sudo xcode-select --switch $CLT"
    elif [[ -x "$CLT/usr/bin/git" ]]; then
      if [[ -n "$ASSUME_YES" ]] || confirm "Use Apple's Command Line Tools instead? (asks for your password)"; then
        run sudo xcode-select --switch "$CLT" || die "couldn't switch. Run: sudo xcode-select --switch $CLT"
        /usr/bin/git --version >/dev/null 2>&1 || die "git still fails. Update or remove the old Xcode, then re-run this installer."
        ok "developer tools work ($CLT)"
      else
        die "fix the developer tools first: sudo xcode-select --switch $CLT"
      fi
    else
      run xcode-select --install || true
      die "install the Command Line Tools in the window that opened, then re-run this installer"
    fi
  fi
fi

# --- Homebrew --------------------------------------------------------------
# Apple Silicon Macs need the native Homebrew in /opt/homebrew. A Homebrew in
# /usr/local on such a Mac is the Intel one (it runs through Rosetta), usually
# brought over from an older Mac. It's left alone; the native one goes next to it.
step "Homebrew"
if [[ -n "$APPLE_SILICON" ]]; then BREW=/opt/homebrew/bin/brew; else BREW=/usr/local/bin/brew; fi
if [[ -x "$BREW" ]]; then
  ok "installed ($BREW)"
else
  if [[ -n "$APPLE_SILICON" && -x /usr/local/bin/brew ]]; then
    warn "found an Intel Homebrew in /usr/local, which runs through Rosetta. Installing the"
    warn "native Apple Silicon Homebrew in /opt/homebrew; the old one is left as it is."
  fi
  run_remote /bin/bash https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
    || die "Homebrew install failed (see its output above). Fix what it reports, then re-run this installer."
fi
add_line "$ZPROFILE" "eval \"\$($BREW shellenv)\""
if [[ -x "$BREW" ]]; then
  eval "$("$BREW" shellenv)"
elif [[ -z "$DRY_RUN" ]]; then
  die "Homebrew install failed"
fi

# --- Homebrew health -------------------------------------------------------
# `brew install` tries to update Homebrew first, but carries on with an
# out-of-date Homebrew when that fails, and then can't find packages for newer
# macOS ("no bottle available"). The usual cause on older installs: shallow
# copies of homebrew/core and homebrew/cask, which `brew update` refuses to
# update. Homebrew 4+ doesn't need those copies, so remove them.
brew_update() { brew update 2>&1; }

# Remove one of the old tap copies. Homebrew 4+ gets packages from its API and
# doesn't need them; older versions do, so download their full history instead.
fix_shallow_tap() {
  local tap="$1" major
  brew tap 2>/dev/null | grep -qx "$tap" || return 0
  major="$(brew --version 2>/dev/null | head -1 | sed -E 's/^Homebrew ([0-9]+).*/\1/')"
  if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 4 )); then
    run brew untap "$tap" && return 0
    run brew untap --force "$tap" && return 0
  fi
  warn "downloading the full history of $tap instead (this can take a while)"
  run git -C "$(brew --repo "$tap")" fetch --unshallow
}

step "Homebrew update"
if [[ -n "$DRY_RUN" ]]; then
  echo "    + brew update"
elif update_out="$(brew_update)"; then
  ok "up to date ($(brew --version 2>/dev/null | head -1))"
elif grep -q "shallow clone" <<<"$update_out"; then
  warn "Homebrew can't update itself: it still has old shallow copies of homebrew/core"
  warn "and homebrew/cask, which newer Homebrew doesn't need."
  if [[ -n "$ASSUME_YES" ]] || confirm "Remove them and update Homebrew? (recommended)"; then
    fix_shallow_tap homebrew/core || true
    fix_shallow_tap homebrew/cask || true
    if update_out="$(brew_update)"; then
      ok "Homebrew updated ($(brew --version 2>/dev/null | head -1))"
    else
      printf '%s\n' "$update_out" | tail -5 | sed 's/^/      /' >&2
      die "brew update still fails. Fix what it reports above, then re-run this installer."
    fi
  else
    die "Homebrew needs updating first. Run: brew untap homebrew/core homebrew/cask && brew update"
  fi
else
  warn "brew update failed; continuing with Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}'). Its output:"
  printf '%s\n' "$update_out" | tail -5 | sed 's/^/      /' >&2
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
step "git, GitHub CLI, AWS CLI, uv, fzf and ffmpeg"
brew_formula git git
brew_formula gh gh
brew_formula awscli aws
brew_formula uv uvx   # the AWS MCP server runs via uvx
brew_formula fzf fzf  # the menu in scry
brew_formula ffmpeg ffmpeg

step "Maven and Java"
brew_formula maven mvn
for v in "${JAVA_VERSIONS[@]}"; do
  if home="$(/usr/libexec/java_home -F -v "$v" 2>/dev/null)"; then
    ok "Java $v already installed ($home)"
  else
    run brew install --cask "temurin@$v"
  fi
done

step "Node.js and puppeteer-core"
# An nvm-managed Node only gets on PATH from ~/.zshrc, which this script
# doesn't read; use it if it's there rather than installing a second Node.
# nvm is loaded in a subshell because it can exit the shell that loads it.
NVM_SH="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
if ! command -v npm >/dev/null 2>&1 && [[ -s "$NVM_SH" ]]; then
  nvm_bin="$( set +eu
              # shellcheck source=/dev/null
              source "$NVM_SH" >/dev/null 2>&1 && nvm use default >/dev/null 2>&1
              dirname "$(command -v npm)" 2>/dev/null )" || true
  if [[ -x "$nvm_bin/npm" ]]; then
    PATH="$nvm_bin:$PATH"
  fi
fi
brew_formula node npm
if npm ls -g puppeteer-core >/dev/null 2>&1; then
  ok "puppeteer-core already installed ($(npm root -g)/puppeteer-core)"
else
  run npm install -g puppeteer-core
fi
# puppeteer-core doesn't download a browser; it drives one that's installed.
[[ -d "/Applications/Google Chrome.app" || -d "$HOME/Applications/Google Chrome.app" ]] \
  || warn "puppeteer-core needs a browser to drive, such as Google Chrome (brew install --cask google-chrome)"

step "Explainer video toolchain"
# The explainer-video skill installs all of this itself on first use; doing it
# here, at the same paths, only makes a dev's first video start faster (the
# skill skips whatever is already there). Narration uses Apple's MLX, so the
# voice part is Apple Silicon only.
# hf_cached <model> — whether a Hugging Face model is already downloaded.
hf_cached() {
  "$EXPLAINER_VENV/bin/python" -c 'import sys
from huggingface_hub import snapshot_download
snapshot_download(sys.argv[1], local_files_only=True)' "$1" >/dev/null 2>&1
}
# hf_fetch <model> — download a Hugging Face model unless it's already there.
hf_fetch() {
  if hf_cached "$1"; then
    ok "$1 already downloaded"
  else
    echo "    + download $1 from Hugging Face"
    [[ -n "$DRY_RUN" ]] || HF_HUB_DISABLE_PROGRESS_BARS=1 "$EXPLAINER_VENV/bin/python" -c 'import sys
from huggingface_hub import snapshot_download
snapshot_download(sys.argv[1])' "$1" >/dev/null 2>&1 \
      || warn "couldn't download $1; it downloads when first used"
  fi
}
explainer_chrome() { find "$EXPLAINER_CHROME_DIR" -name chrome-headless-shell -type f -perm +111 2>/dev/null | head -1; }

if [[ -n "$INTERACTIVE" ]] && ! confirm "Set up the tools for explainer videos? (about 2 GB)"; then
  ok "skipped (the explainer-video skill installs them when first used)"
else
  node_major="$(node -v 2>/dev/null | sed -E 's/^v([0-9]+).*/\1/')" || true
  [[ "${node_major:-0}" -ge 22 || -n "$DRY_RUN" ]] \
    || warn "explainer videos need Node.js 22 or later (you have $(node -v 2>/dev/null || echo none))"

  # Headless Chrome, for checking and rendering the Motion Canvas scenes.
  if chrome="$(explainer_chrome)" && [[ -n "$chrome" ]]; then
    ok "chrome-headless-shell already installed ($("$chrome" --version 2>/dev/null || echo "$chrome"))"
  else
    run npx --yes "$EXPLAINER_BROWSERS" install chrome-headless-shell@stable --path "$EXPLAINER_CHROME_DIR" \
      || warn "couldn't download chrome-headless-shell; the explainer-video skill will try again"
  fi

  # Narration: Kokoro text-to-speech on MLX, in a venv at a short path
  # (espeak-ng can't find its data when the path is long).
  if [[ "$(uname -m)" != arm64 ]]; then
    warn "skipping narration: its text-to-speech needs Apple Silicon"
  else
    if [[ -x "$EXPLAINER_VENV/bin/python" ]] \
       && "$EXPLAINER_VENV/bin/python" -c 'import mlx_audio, misaki, mlx_whisper, en_core_web_sm' 2>/dev/null; then
      ok "narration venv already set up ($EXPLAINER_VENV)"
    else
      { [[ -x "$EXPLAINER_VENV/bin/python" ]] || run uv venv -q -p 3.12 "$EXPLAINER_VENV"; } \
        && run uv pip install -q -p "$EXPLAINER_VENV/bin/python" "${EXPLAINER_PACKAGES[@]}" \
        || warn "couldn't set up the narration venv; the explainer-video skill will try again"
    fi
    hf_fetch "$EXPLAINER_VOICE"
    # Whisper only checks pronunciation by transcribing the narration back.
    if hf_cached "$EXPLAINER_WHISPER"; then
      ok "$EXPLAINER_WHISPER already downloaded"
    elif [[ -n "$DRY_RUN" ]]; then
      echo "    + (ask) download $EXPLAINER_WHISPER, default no"
    elif confirm "Also download Whisper, to check pronunciation? (1.5 GB, optional)" N; then
      hf_fetch "$EXPLAINER_WHISPER"
    else
      ok "skipped Whisper (downloaded when first needed)"
    fi

    # Smoke test: say something and check a WAV comes out.
    if [[ -z "$DRY_RUN" ]]; then
      tts_out="$(mktemp -d)"
      if "$EXPLAINER_VENV/bin/python" -m mlx_audio.tts.generate --model "$EXPLAINER_VOICE" --voice af_heart \
           --lang_code a --text "Hello from Kokoro" --join_audio --output_path "$tts_out" \
           --file_prefix kokoro_test --audio_format wav >/dev/null 2>&1 \
         && [[ -s "$tts_out/kokoro_test.wav" ]]; then
        ok "narration works (Kokoro said hello)"
      else
        warn "the narration test didn't produce audio; the explainer-video skill will try to repair it"
      fi
      rm -rf "$tts_out"
    fi
  fi
fi

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

# NODE_PATH lets require() find global npm packages such as puppeteer-core.
# The global folder sits next to whichever node is on PATH (Homebrew or nvm),
# so it's worked out from that before each prompt, which also follows
# `nvm use`, without running npm on every prompt. Other NODE_PATH entries stay.
# (read, not $(cat <<…): bash 3.2 misparses quotes in a heredoc inside $(…))
IFS= read -r -d '' NODE_BLOCK <<'ZSH' || true
_workbench_node_path() {
  local node="${commands[node]:-}" dir
  [[ -n "$node" ]] || return 0
  # Not resolving symlinks: Homebrew's bin/node links into its Cellar, but
  # its global packages are in /opt/homebrew/lib/node_modules.
  dir="${node:h:h}/lib/node_modules"
  [[ "$dir" != "${_workbench_node_modules:-}" ]] || return 0
  local -a parts=("${(@s.:.)NODE_PATH}")
  parts=("$dir" "${(@)parts:#${_workbench_node_modules:-}}")
  _workbench_node_modules="$dir"
  export NODE_PATH="${(j.:.)parts}"
}
autoload -Uz add-zsh-hook && add-zsh-hook precmd _workbench_node_path
_workbench_node_path
ZSH
add_block "$ZSHRC" "scrubs workbench node" "${NODE_BLOCK%$'\n'}"

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
# A GITHUB_TOKEN/GH_TOKEN in the environment stops 'gh auth login' from storing
# a login, and gh hands that token to git instead. Such tokens usually lack the
# 'repo' scope, so private SmartScrubs repos come back as "not found". Explain
# where the token comes from and how to get rid of it, once.
TOKEN_VARS=""
[[ -n "${GITHUB_TOKEN:-}" ]] && TOKEN_VARS="GITHUB_TOKEN"
[[ -n "${GH_TOKEN:-}" ]] && TOKEN_VARS="${TOKEN_VARS:+$TOKEN_VARS and }GH_TOKEN"
TOKEN_ADVICE_SHOWN=""
token_advice() {
  [[ -n "$TOKEN_ADVICE_SHOWN" ]] && return 0
  TOKEN_ADVICE_SHOWN=1
  local hits f rc_files=() verb="is"
  [[ "$TOKEN_VARS" == *" and "* ]] && verb="are"
  warn "$TOKEN_VARS $verb set in your environment. 'gh auth login' can't store a login while"
  warn "that's there, and git sends that token to GitHub instead of your login. Tokens like this"
  warn "usually can't read private SmartScrubs repos."
  for f in ~/.zshenv ~/.zprofile ~/.zshrc ~/.zlogin ~/.bash_profile ~/.bashrc ~/.profile ~/.config/fish/config.fish; do
    [[ -f "$f" ]] && rc_files+=("$f")
  done
  hits=""
  # -H: always show the file name. The value itself is masked; it's a secret.
  [[ ${#rc_files[@]} -gt 0 ]] && hits="$(grep -H -n -E '(GITHUB_TOKEN|GH_TOKEN)=' "${rc_files[@]}" 2>/dev/null \
    | sed -E "s|^$HOME|~|; s/(TOKEN=)[\"']?[^\"' ]+[\"']?/\1…/" || true)"
  if [[ -n "$hits" ]]; then
    echo "      It's set here:" >&2
    while IFS= read -r f; do echo "        $f" >&2; done <<<"$hits"
  else
    echo "      It isn't set in your shell startup files, so it comes from somewhere else:" >&2
    echo "      a tool like direnv or 1Password, your terminal app's profile, or launchctl setenv." >&2
  fi
  echo "      To fix it:" >&2
  echo "        1. Delete that line (or the setting that creates it)." >&2
  echo "        2. Open a new terminal and check it's gone:  env | grep -E '^(GITHUB_TOKEN|GH_TOKEN)='" >&2
  echo "        3. Sign in and let git use that login:  gh auth login --web && gh auth setup-git" >&2
  echo "        4. Re-run this installer." >&2
  echo "      If another tool needs the token, give it the 'repo' scope at github.com/settings/tokens instead." >&2
}
if ! command -v gh >/dev/null 2>&1; then
  [[ -n "$DRY_RUN" ]] && echo "    + gh auth login --hostname github.com --git-protocol https --web"
elif gh auth status --hostname github.com >/dev/null 2>&1; then
  ok "signed in to GitHub as $(gh api user --jq .login 2>/dev/null || echo '?')"
elif [[ -n "$TOKEN_VARS" ]]; then
  token_advice
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
elif [[ -n "$TOKEN_VARS" ]]; then
  warn "git can't access SmartScrubs/scrubs."
  token_advice
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

# AGENTS.md intent for new workspaces when --intent isn't given
# (default: "default"; see: repomancer --list-intents)
#REPOMANCER_INTENT="feature"

# Repo with one intents/<name>/AGENTS.md per intent
#REPOMANCER_AGENTS_REPO="https://github.com/SmartScrubs/agents-md.git"

# Update repomancer and scry automatically, at most once an hour (default: yes)
#REPOMANCER_AUTO_UPDATE="no"

# scry: close the iTerm2 tab or pane when Claude Code exits (default: yes)
#SCRY_CLOSE_ON_EXIT="no"
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

step "repomancer and scry commands"
for tool in repomancer scry; do
  if [[ "$(readlink "$LOCAL_BIN/$tool" 2>/dev/null)" == "$SCRIPT_DIR/$tool" ]]; then
    ok "$LOCAL_BIN/$tool already links to $SCRIPT_DIR/$tool"
  else
    run mkdir -p "$LOCAL_BIN"
    run chmod +x "$SCRIPT_DIR/$tool"
    run ln -sf "$SCRIPT_DIR/$tool" "$LOCAL_BIN/$tool"
  fi
  # Warn if another program called $tool comes first on PATH.
  found="$(PATH="$LOCAL_BIN:$PATH" command -v "$tool" 2>/dev/null || true)"
  if [[ -n "$found" && "$found" != "$LOCAL_BIN/$tool" ]]; then
    warn "'$tool' runs $found, not $LOCAL_BIN/$tool; check your PATH"
  fi
done
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
      2. See your workspaces:      scry
         or start one directly:    repomancer my-feature

    Anything skipped above can be finished later with:
      gh auth login && gh auth setup-git
      aws login
      claude auth login
EOF

# Offer to open scry in iTerm2. A new iTerm2 session loads the updated shell
# config, so scry is on PATH there even on a fresh Mac. If iTerm2 isn't
# running yet, use the window it opens at launch instead of adding a second.
if [[ -d "/Applications/iTerm.app" || -d "$HOME/Applications/iTerm.app" ]] \
   && [[ -x "$LOCAL_BIN/scry" || -n "$DRY_RUN" ]]; then
  if [[ -n "$DRY_RUN" ]]; then
    echo
    echo "    + (ask) open scry in iTerm2"
  elif [[ -n "$INTERACTIVE" ]] && echo && confirm "Open scry in iTerm2 now?"; then
    echo "    (The first time, macOS asks whether this terminal may control iTerm2: allow it.)"
    osascript - "scry" >/dev/null <<'APPLESCRIPT' || warn "couldn't open iTerm2; run scry in a new terminal"
on run argv
  set cmd to item 1 of argv
  set wasRunning to (application "iTerm" is running)
  tell application "iTerm"
    activate
    if not wasRunning then
      repeat 20 times
        if (count of windows) > 0 then exit repeat
        delay 0.25
      end repeat
    end if
    if (count of windows) is 0 then
      set s to current session of (create window with default profile)
    else if wasRunning then
      tell current window
        set t to (create tab with default profile)
      end tell
      set s to current session of t
    else
      set s to current session of current window
    end if
    tell s to write text cmd
  end tell
end run
APPLESCRIPT
  fi
fi

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
