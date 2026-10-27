# Handoff: maintaining the scrubs workbench

For whoever works on this repo next, person or agent. [README.md](README.md) explains how to use the tools; this file covers how they fit together, the conventions they follow, how changes are tested, and what's still open.

## What's here

| File | What it is |
|---|---|
| `install.sh` | The interactive installer for a new Mac, usually run with the one-liner in the README. Each `step` installs one thing and skips it if it's already there, so it's safe to run again. |
| `repomancer` | Clones `SmartScrubs/scrubs` into `<root>/<branch>`, creates the branch, installs the bundled Maven jars, copies an intent `AGENTS.md` from `SmartScrubs/agents-md`, and starts Claude Code as `ws+<branch>`. |
| `scry` | An fzf menu of the workspaces that opens them in iTerm2 tabs or panes, with a plain menu when fzf is missing. |

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
- **Fakes:**
  - scry: a temporary `REPOMANCER_ROOT` with throwaway git repos.
  - Self-update: a local bare repo standing in for `origin`.
  - VPN and nvm cases: stub commands on a reduced `PATH`.
  - Failure paths: run a step with `PATH=/usr/bin:/bin`, so `npx`, `uv` and `node` are missing.

## Things that bit before

| Area | What to know |
|---|---|
| scry live refresh | The watcher polls every 2 s and sends fzf `reload-sync` through `--listen`. Its signature is the list of workspace folders plus the times of `.git/HEAD` and `.git/config`. It must **not** include the `.git` folder's own time: building the list runs `git status`, which changes that time, so the list reloaded every 2 s. `--track --id-nth=1` keeps the cursor on its workspace, but only fzf 0.66+ has it, so scry checks for it first. |
| Maven jars | The scrubs poms install `Libraries/*.jar` into `~/.m2` only during `mvn clean`, so `repomancer` runs `mvn -B -q -N clean` on just those poms. They're found with `git grep '<goal>install-file</goal>'`. |
| VPN check | It looks at tunnel interfaces (`utun`, `ppp`, `ipsec`…) that have a real IPv4 address. It asks Cisco's `vpn state` only when a tunnel exists, because that command takes about 2 s. `scutil --nc list` is wrong for Cisco. `ALLOW_VPN=1` skips the check. |
| nvm | Sourcing `nvm.sh` can exit the shell that sources it (e.g. when `NPM_CONFIG_PREFIX` is set), so the installer sources it in a subshell, only to find `npm`. |
| NODE_PATH | The `.zshrc` block uses `${commands[node]:h:h}/lib/node_modules` without `:A`, because Homebrew's `node` links into its Cellar while global packages live in `/opt/homebrew/lib/node_modules`. A `precmd` hook follows `nvm use`. |
| `gh` and private repos | A `GITHUB_TOKEN` in someone's shell takes priority over `gh`'s own sign-in, and usually can't read private repos. `gh` then reports "Not Found" even though `git` works. The installer's GitHub step explains this. |
| Claude plugins | Claude Code only auto-updates Anthropic's marketplaces. For ours, the installer sets `autoUpdate: true` on the marketplace's entry under `extraKnownMarketplaces` in `~/.claude/settings.json`. |

## Contracts with other repos

- **`SmartScrubs/scrubs`:** `repomancer` relies on the `install-file` executions in its poms, and on its default branch (currently `zenbu`) when no base branch is given.
- **`SmartScrubs/agents-md`:** holds one `AGENTS.md` per intent, cached in `~/.cache/repomancer/agents`.
- **`SmartScrubs/smartscrubs-ai-skills`:** a private Claude Code marketplace. The installer installs its `video-explainers` plugin, which contains the `explainer-video` skill.
- **The explainer toolchain** must match that skill's `scripts/setup.sh`.
  - Same paths: `~/.cache/explainer-venv` and `~/.cache/explainer-chrome`. Both can be changed with `EXPLAINER_VENV` and `EXPLAINER_CHROME_DIR`, which the skill reads too.
  - Same pinned versions, set at the top of `install.sh`. If the skill changes its pins, change them here too.
  - The skill skips anything it finds there, so the installer's step only saves time on the first video.
  - The venv path must stay short: espeak-ng fails when its data path is long.
  - Motion Canvas is frozen at 3.17.2; don't upgrade it. Don't add Remotion: its free license doesn't cover a team our size.

## Open items

- **The private marketplace install hasn't been seen working.** Running `claude plugin marketplace add SmartScrubs/smartscrubs-ai-skills` from the installer on a fresh Mac is untested. It needs the GitHub sign-in step, which runs earlier, to have set up git access.
- **Whisper:** its download is offered (default no) but has never been run end to end.
- **Intel Macs:** the explainer step skips narration on non-Apple-Silicon Macs. That branch was checked by reading, not run on Intel.
