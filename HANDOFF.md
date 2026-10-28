# Handoff: maintaining the scrubs workbench

For whoever works on this repo next, person or agent. [README.md](README.md) explains how to use the tools; this file covers how they fit together, the conventions they follow, how changes are tested, and what's still open.

## What's here

| File | What it is |
|---|---|
| `install.sh` | The interactive installer for a new Mac, usually run with the one-liner in the README. Each `step` installs one thing and skips it if it's already there, so it's safe to run again. |
| `repomancer` | Clones `SmartScrubs/scrubs` into `<root>/<branch>`, creates the branch, installs the bundled Maven jars, copies an intent `AGENTS.md` from `SmartScrubs/agents-md`, and starts Claude Code as `ws+<branch>`. |
| `scry` | An fzf menu of the workspaces that opens them in iTerm2 tabs or panes, or moves them to the Trash, with a plain menu when fzf is missing. |

## How a change reaches people

- `install.sh` clones this repo to `~/tools/scrubs-ws-claude-workbench` and symlinks `repomancer` and `scry` into `~/.local/bin`.
- Both scripts update themselves by fast-forwarding that clone to `origin/main`.
  - They check at most once an hour, with the stamp file `~/.cache/repomancer/last-update-check`.
  - They only update when the clone is clean and can fast-forward.
  - The fetch can't hang on a password prompt or a dead network: it uses BatchMode SSH, a 5 s connect timeout and a low-speed limit.
- After an update, `repomancer` restarts itself, with `REPOMANCER_UPDATED` stopping it from looping. `scry` restarts and shows a status line.
- So **pushing to `main` is a release**: everyone with auto-update on gets it within the hour. Installer changes only reach people who run the installer again.
- Both scripts wrap their whole body in `{ …; exit; }`. bash reads the file as it runs, so without that, updating a running script would break it.

## Conventions

- **Working agreement:** commit after each change, then ask before pushing. Update the README in the same commit as the behaviour it describes.
- **bash 3.2:** macOS's `/bin/bash` is 3.2, and the one-liner runs `install.sh` with it.
  - Don't use `${var,,}` or associative arrays.
  - Expand arrays that may be empty as `"${arr[@]+"${arr[@]}"}"`, or `set -u` fails on them.
  - A heredoc containing an apostrophe inside `$( … )` misparses. Use `IFS= read -r -d '' VAR <<'EOF' || true` instead (see the NODE_PATH block in `install.sh`).
- **install.sh helpers:**
  - Output: `step`, `ok`, `warn` and `die`.
  - `run` prints a command and runs it, except with `--dry-run`.
  - Questions: `confirm` and `ask`. They read from `/dev/tty`, so they work under `curl | bash`. `confirm` returns "no" when not interactive.
  - `add_block` adds a marked block to `~/.zshrc` or `~/.zprofile` once.
- **install.sh modes:** `DRY_RUN`, `ASSUME_YES` (`--yes`) and `INTERACTIVE`. Every new step must handle all three.
- **Failures:** optional extras only `warn` when they fail, so the rest of the installer still runs. Only things later steps need may `die`.
- **`set -e` with pipefail:** a failing command in `x="$(cmd | sed …)"` exits the installer. Add `|| true` when failing is fine.

## How changes were tested

- `bash -n` and `/bin/bash -n` on every script, plus `/bin/bash install.sh --dry-run` (should exit 0).
- **One installer step at a time:** cut the helpers and one step into a separate script:
  ```sh
  { sed -n '1,/^SHELL_CHANGED=""/p' install.sh; sed -n '/^step "X"/,/^step "Y"/p' install.sh; } > step.sh
  ```
  Then run it with `--yes`, `--dry-run`, or interactively.
- **fzf menus and installer questions:** run them in a detached `tmux` session, send keys with `tmux send-keys` and read the screen with `tmux capture-pane -p`.
  - Filter scry's list with `^name`: a plain query also matches the status column, so `clean` finds every clean workspace.
  - Wait a second or so between keys: after an action the menu restarts, and keys sent too early go to the wrong prompt.
- **Fakes:**
  - scry: a temporary `REPOMANCER_ROOT` with throwaway git repos.
  - Self-update: a local bare repo standing in for `origin`.
  - Deleting a workspace that's in use: start `sleep 600` from inside the workspace folder.
  - VPN and nvm cases: stub commands on a reduced `PATH`.
  - Failure paths: run a step with `PATH=/usr/bin:/bin`, so `npx`, `uv` and `node` are missing.
- **Real runs:** run the whole installer in an iTerm2 pane (open one with AppleScript: `split vertically with default profile`, then `write text`).
  - Read the result back with AppleScript's `contents of session`, which includes the scrollback.
  - Pick the pane by its text, e.g. it contains `==> VPN`. Make sure you don't match your own Claude Code pane, which shows the same words.
  - Run the copy in `~/tools/scrubs-ws-claude-workbench` (after `git pull`), not your working checkout: the installer points `repomancer` and `scry` at the checkout it runs from.

## Things that bit before

| Area | What to know |
|---|---|
| scry live refresh | The watcher polls every 2 s and sends fzf `reload-sync` through `--listen`. Its signature is the list of workspace folders plus the times of `.git/HEAD` and `.git/config`. It must **not** include the `.git` folder's own time: building the list runs `git status`, which changes that time, so the list reloaded every 2 s. `--track --id-nth=1` keeps the cursor on its workspace, but only fzf 0.66+ has it, so scry checks for it first. |
| scry delete | To tell whether a workspace is in use, scry finds every process whose working folder is in it, using `/usr/sbin/lsof -d cwd` (about 0.4 s). It calls `lsof` by its full path: `/usr/sbin` can be missing from `PATH`, and then the check would find nothing and the workspace would be deleted anyway. A workspace counts as unpushed when any local branch has commits that aren't on `origin`, not just the branch it's on. It moves the folder with macOS's `trash` command and uses `rm -rf` only where that command doesn't exist. Claude Code's transcripts in `~/.claude/projects` stay. That's harmless: `repomancer` only resumes a session for a folder that already exists. |
| Maven jars | The scrubs poms install `Libraries/*.jar` into `~/.m2` only during `mvn clean`, so `repomancer` runs `mvn -B -q -N clean` on just those poms. They're found with `git grep '<goal>install-file</goal>'`. |
| VPN check | It looks at tunnel interfaces (`utun`, `ppp`, `ipsec`…) that have a real IPv4 address. It asks Cisco's `vpn state` only when a tunnel exists, because that command takes about 2 s. `scutil --nc list` is wrong for Cisco. `ALLOW_VPN=1` skips the check. |
| nvm | Sourcing `nvm.sh` can exit the shell that sources it (e.g. when `NPM_CONFIG_PREFIX` is set), so the installer sources it in a subshell, only to find `npm`. |
| NODE_PATH | The `.zshrc` block uses `${commands[node]:h:h}/lib/node_modules` without `:A`, because Homebrew's `node` links into its Cellar while global packages live in `/opt/homebrew/lib/node_modules`. A `precmd` hook follows `nvm use`. |
| `gh` and private repos | A `GITHUB_TOKEN` in someone's shell takes priority over `gh`'s own sign-in, and usually can't read private repos. `gh` then reports "Not Found" even though `git` works. The installer's GitHub step explains this. |
| Homebrew questions | In a terminal, Homebrew 7 asks "Do you want to proceed with the installation? [y/n]" before installing anything with dependencies (never without a terminal, and never with `--dry-run`, so dry runs don't show it). The installer sets `HOMEBREW_NO_ASK=1` before its first `brew install`; an environment variable, rather than `--yes`, because older Homebrew rejects unknown flags. |
| Hugging Face models | The model folders in `~/.cache/huggingface/hub/models--…` only hold links and look a few KB in size. The weights are in the shared `~/.cache/huggingface/hub/blobs/`. Check a model with `snapshot_download(…, local_files_only=True)`, as `hf_cached` in `install.sh` does. |
| Claude plugins | Claude Code only auto-updates Anthropic's marketplaces. For ours, the installer sets `autoUpdate: true` on the marketplace's entry under `extraKnownMarketplaces` in `~/.claude/settings.json`. |
| Private marketplace clones | Claude Code (2.1.x) clones a GitHub marketplace over SSH when SSH to GitHub is set up, otherwise over HTTPS, and retries with the other one if the first fails. Neither can prompt (`GIT_TERMINAL_PROMPT=0`, SSH `BatchMode`). So a fresh Mac without an SSH key works over HTTPS, using the git sign-in from `gh auth setup-git`. Setting `CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1` forces HTTPS. What fails is having no access at all, so `can_read_github` checks first: without access, the installer warns once with the fix and skips the marketplace's plugins and auto-update. |

## Contracts with other repos

- **`SmartScrubs/scrubs`:** `repomancer` relies on the `install-file` executions in its poms, and on its default branch (currently `zenbu`) when no base branch is given.
- **`SmartScrubs/agents-md`:** holds one `AGENTS.md` per intent, cached in `~/.cache/repomancer/agents`.
- **`SmartScrubs/smartscrubs-ai-skills`:** a private Claude Code marketplace. The installer installs its `video-explainers` plugin, which contains the `explainer-video` skill.
- **Plugins that need tools on the Mac:** `jdtls-lsp` starts a `jdtls` command from `PATH` (Homebrew's `jdtls`, which brings its own JDK). `aws-transform` runs its MCP server with `uvx` and installs AWS's `atx` CLI itself when a transformation first needs it, so the installer doesn't install `atx`.
- **The explainer toolchain** must match that skill's `scripts/setup.sh`.
  - Same paths: `~/.cache/explainer-venv` and `~/.cache/explainer-chrome`. Both can be changed with `EXPLAINER_VENV` and `EXPLAINER_CHROME_DIR`, which the skill reads too.
  - Same pinned versions, set at the top of `install.sh`. If the skill changes its pins, change them here too.
  - The skill skips anything it finds there, so the installer's step only saves time on the first video.
  - The venv path must stay short: espeak-ng fails when its data path is long.
  - Motion Canvas is frozen at 3.17.2; don't upgrade it. Don't add Remotion: its free license doesn't cover a team our size.
- **Claude Code internals that `scry`'s Claude line reads.** None of these are documented, so a Claude Code update can break them. When that happens, the usage or model name is left out quietly instead of failing. Check here first if the line goes missing.
  - **Usage:** `GET https://api.anthropic.com/api/oauth/usage` with the header `anthropic-beta: oauth-2025-04-20`. It's signed in with the `accessToken` from the Keychain item `Claude Code-credentials` (JSON, under `claudeAiOauth`). `scry` reads `five_hour` and `seven_day` (`utilization`, `resets_at`).
  - **Model names:** Claude Code's cached model list, `~/.claude/cache/model-catalog/*-cc.json`. `catalog.config.provider_alias_targets` maps aliases such as `fable` to model IDs, `catalog.config.models` gives their names, and `catalog.state.model` is the model Claude Code last chose.
  - **The token:** it stays inside Python and never goes into a command line, where `ps` would show it. `scry` never refreshes an expired token, because that would get in the way of Claude Code's own refresh; it waits for Claude Code to renew it. The cache, `~/.cache/scry/usage.json`, holds only the percentages and reset times.

## Verified on a real Mac

These steps have been run in full on an Apple Silicon Mac, not just dry-run:
- **The VPN check** stopped for Cisco Secure Client, and continued once the VPN was off.
- **The explainer toolchain**, including Whisper. Whisper correctly transcribed Kokoro's narration with Hugging Face access switched off.
- **The `video-explainers` plugin** installed from the private marketplace, and auto-update was turned on.
- **A second full run** changed nothing.

## Open items

- **The private marketplace on a fresh Mac:** a Mac without an SSH key hasn't been tried end to end. It should work: Claude Code's clone code uses HTTPS when SSH isn't set up (see "Private marketplace clones" above), and an HTTPS clone with SSH disabled worked using the git sign-in.
- **Intel Macs:** the explainer step skips narration on non-Apple-Silicon Macs. That branch was checked by reading, not run on Intel.
