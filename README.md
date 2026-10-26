# repomancer — Claude Code workspace launcher

`repomancer` gives you a fresh clone of [SmartScrubs/scrubs](https://github.com/SmartScrubs/scrubs) on a new branch, then opens Claude Code in it.

```sh
repomancer my-feature              # branch from the repo's default branch (currently `zenbu`)
repomancer my-feature main         # branch from `main` instead
repomancer my-bug -i debug         # start with the Debug instructions for Claude
repomancer --list-intents          # show the available intents
```

What it does:

1. Checks that the branch names are valid, that the base branch exists on GitHub, and that `claude` is on your `PATH`.
2. Clones the repo into `~/Documents/AIProjects/my-feature`, wherever you run `repomancer` from (a `/` in the branch name becomes `-`, so `feature/x` goes in `feature-x/`). See [Configuration](#configuration) to use a different folder.
3. Creates the branch from the base branch (the second argument, or the repo's default branch if you leave it out) and switches to it. If the branch already exists on `origin`, it checks that one out instead and ignores the base branch.
4. Points the branch at `origin/<branch>` and sets `push.autoSetupRemote`, so a plain `git push` works the first time.
5. Installs the jars that `scrubs` ships in its `Libraries/` folders because no public Maven repo has them (`mysterymeat:jconn4`, `JTOpen` and `stringtemplate-keyvaluecoding`) into `~/.m2`. The poms only install them during `mvn clean`, so without this, any other build fails on a new Mac. repomancer runs `mvn clean` in just the modules that do this. The first time, Maven downloads its plugins, which takes about a minute; after that it takes a second or two. If it fails, repomancer prints the command to retry and opens Claude anyway.
6. Copies an `AGENTS.md` for the chosen [intent](#intents) into the workspace, so Claude starts out knowing what kind of work it's there for.
7. Runs `claude --name "ws+my-feature"`, so the session is easy to find in `/resume` and in the terminal title.

If `~/Documents/AIProjects/my-feature` already exists, `repomancer my-feature` reopens it instead. It resumes the most recent Claude session in that folder (`claude --continue`), or starts a new `ws+my-feature` session if there isn't one. The base branch and intent are ignored in that case, and its `AGENTS.md` is left as it is.

## Intents

Each new workspace gets an `AGENTS.md` from the private [SmartScrubs/agents-md](https://github.com/SmartScrubs/agents-md) repo, which holds one per intent: `analyse`, `debug`, `feature`, `project`, `chores` and `default`. repomancer uses the first of these that's set:

1. `--intent debug` (or `-i debug`) on the command line
2. `REPOMANCER_INTENT` in `~/.config/repomancer/config`, or as an environment variable
3. `default`

- **Names:** case-insensitive. An unknown intent stops repomancer before it clones anything, and lists the valid ones.
- **Updates:** repomancer keeps a copy of the agents repo in `~/.cache/repomancer/agents` and updates it on every run. If GitHub can't be reached, it uses that copy.
- **Not committed:** the copied `AGENTS.md` is excluded from git in that workspace only (`.git/info/exclude`), so it can't be committed to `scrubs` by accident. If `scrubs` ever gets its own `AGENTS.md`, that one is kept.
- **Changing them:** edit or add intents in the agents repo, not in a workspace. See its README.

Claude Code reads `AGENTS.md` when there's no `CLAUDE.md` in the workspace or above it.

## scry: your workspaces at a glance

`scry` lists every workspace in your workspace folder, newest first. For each one it shows the branch, the intent, how long ago you last worked on it, and whether it has uncommitted or unpushed changes. A side panel previews the highlighted workspace's `git status` and recent commits. The list updates by itself while it's open, so a workspace you just started shows up as soon as `repomancer` starts cloning it (this needs fzf 0.45 or later).

```sh
scry           # interactive menu
scry --list    # just print the list
scry --update  # update scry and repomancer now
```

| Key | Action |
|-----|--------|
| type | filter the list |
| <kbd>Enter</kbd> | open the workspace in a new iTerm2 tab (in a new window if iTerm2 has none open). It runs `repomancer <workspace>`, so the Claude session resumes |
| <kbd>⌃V</kbd> | open it in a new iTerm2 pane beside the one `scry` runs in |
| <kbd>⌃H</kbd> | open it in a new iTerm2 pane below the one `scry` runs in |
| <kbd>⌃N</kbd> or **+ New workspace…** | asks for a branch, an optional base branch and an intent, shows a summary to confirm, then runs `repomancer` in a new tab (<kbd>⌃V</kbd>/<kbd>⌃H</kbd> on **+ New workspace…** start it in a pane instead). <kbd>Esc</kbd> cancels at any step; without fzf, type `q` |
| <kbd>⌃S</kbd> or **⚙ Settings…** | change the workspace folder, default intent or repos (each one checked before saving), turn automatic updates on or off, check for updates now, or open the config file in your editor |
| <kbd>Esc</kbd> | quit |

In iTerm2, <kbd>⌃H</kbd> and Backspace are different keys unless you've turned on *Delete key sends ^H* in the profile's Keys settings. With that on, Backspace in `scry` opens a pane instead of deleting a character.

When Claude Code exits, `scry` closes the tab or pane it opened. If `repomancer` fails, for example on a clone error, the tab stays open so you can read the error. To keep tabs open, turn this off under **⚙ Settings…** or set `SCRY_CLOSE_ON_EXIT="no"` in `~/.config/repomancer/config`. iTerm2 closes a session when its shell exits as long as the profile's *Session → When session ends* setting is left at its default.

The first time `scry` opens a tab, macOS asks whether your terminal may control iTerm2. Allow it. Without fzf, `scry` shows a numbered menu with the same options.

## Setup (new Mac)

`install.sh` sets up everything the workbench needs, then walks you through signing in. It skips anything already installed or signed in, so it's safe to re-run.

**Turn off your VPN first.** VPNs often block or intercept the downloads the installer needs (Homebrew, GitHub, claude.ai), and the install then fails partway. The installer checks before it starts. If a VPN is connected, it names it (e.g. Cisco Secure Client) and waits: turn the VPN off and press Enter to continue, or type `q` to stop. With `--yes` it stops. If you have to stay on the VPN, put `ALLOW_VPN=1` in front of the command to skip the check.

| What | How it's installed |
|------|--------------------|
| Apple developer tools | checks that Apple's `git` works. If the selected tools are broken (e.g. an old Intel-only Xcode on an Apple Silicon Mac), offers to switch to the Command Line Tools, or opens their installer |
| Homebrew | official installer, plus `brew shellenv` in `~/.zprofile`. On Apple Silicon always the native one in `/opt/homebrew`; an Intel Homebrew in `/usr/local` (from an older Mac) is left alone |
| Homebrew update | runs `brew update` first. If an old Homebrew can't update because of leftover shallow `homebrew/core`/`homebrew/cask` copies, it offers to remove them (Homebrew 4+ doesn't need them), or for older Homebrew downloads their full history |
| Oh My Zsh | official installer, run so it never replaces an existing `~/.zshrc`. Set to update itself automatically, without the "update now?" question when a terminal opens |
| git, GitHub CLI, AWS CLI, uv, fzf, ffmpeg | `brew install` |
| Maven | `brew install maven` |
| Java 11, 21, 25 | `brew install --cask temurin@<version>`, unless a JDK of that version is already installed |
| iTerm2, VS Code, Sublime Text | `brew install --cask`, plus the `code` and `subl` commands (linked into `~/.local/bin` if you installed the app by hand) |
| Markdown preview for Sublime Text | Package Control plus the [MarkdownPreview](https://packagecontrol.io/packages/MarkdownPreview) package, which Package Control installs the next time Sublime starts |
| Claude Code | official installer (`curl -fsSL https://claude.ai/install.sh \| bash`) |
| Claude Code plugins: sentry, postman, superpowers, comfy-cloud | `claude plugin install` (from `claude-plugins-official` and `comfy-skills`) |
| AWS skills and AWS MCP server for Claude Code | `aws configure agent-toolkit --yes` |
| Claude Code extension for VS Code | `code --install-extension anthropic.claude-code` |
| `repomancer` and `scry` commands | symlinks in `~/.local/bin`, which is added to `PATH` in `~/.zshrc` |

It asks before each sign-in step:

| Step | What happens |
|------|--------------|
| git name and email | Asks for them if they aren't set yet, and offers to change them if they are |
| GitHub | `gh auth login` in your browser, then `gh auth setup-git` so git can clone private SmartScrubs repos over HTTPS. Then it checks you can reach `SmartScrubs/scrubs`. If a `GITHUB_TOKEN` or `GH_TOKEN` is set in your shell, it tells you which startup file sets it and how to remove it: such tokens block `gh auth login` and usually can't read private repos |
| AWS | Choose `aws login` (browser sign-in with your console login), `aws configure sso`, `aws configure` (access keys), or skip |
| Claude Code | `claude auth login` in your browser |

Run it straight from GitHub. It signs you in to GitHub, then clones this repo into `~/tools/scrubs-ws-claude-workbench`:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/SmartScrubs/scrubs-ws-claude-workbench/main/install.sh)"
```

Or from a clone:

```sh
# git comes with Apple's command line tools; macOS offers to install them
# the first time you run git.
git clone https://github.com/SmartScrubs/scrubs-ws-claude-workbench.git ~/tools/scrubs-ws-claude-workbench
cd ~/tools/scrubs-ws-claude-workbench

./install.sh --dry-run   # optional: show what it would do
./install.sh
```

Options:

- `--dry-run` prints what it would do without changing anything.
- `--yes` skips every question, and with it the sign-in steps (useful for re-running just to install updates).
- `ALLOW_VPN=1` skips the VPN check.
- `WORKBENCH_DIR` sets where the workbench repo is cloned when the script runs from a URL instead of a checkout. The default is `~/tools/scrubs-ws-claude-workbench`.

At the end it checks every MCP server Claude Code can see (`claude mcp list`) and lists any that need signing in or failed to connect. Sign in to the ones you need from Claude Code with `/mcp`, then open a new terminal.

Finally, it offers to open `scry` in iTerm2: in a new tab if iTerm2 is already running, otherwise in the window iTerm2 opens when it starts.

### Markdown preview in Sublime Text

Open a `.md` file, press <kbd>⌘</kbd><kbd>⇧</kbd><kbd>P</kbd> and run **Markdown Preview: Preview in Browser**. If Sublime was open while the installer ran, restart it first so Package Control can install the package.

### Java versions

The installer adds this to `~/.zshrc`:

- `JAVA_HOME` defaults to Java 25. Set `JAVA_DEFAULT=21 ./install.sh` before the first install to choose a different default.
- `jdk 11`, `jdk 21` or `jdk 25` switches the current terminal to that version. `java` and `mvn` both follow it.

```sh
jdk 11
mvn clean install
```

### Manual setup

If you already have the tools, you only need `repomancer` on your `PATH`:

```sh
ln -s "$PWD/repomancer" ~/.local/bin/repomancer
```

## Configuration

| Setting   | Default                                      | Purpose                     |
|-----------|----------------------------------------------|-----------------------------|
| `REPOMANCER_ROOT` | `~/Documents/AIProjects`                     | Folder where workspaces go  |
| `REPOMANCER_REPO` | `https://github.com/SmartScrubs/scrubs.git`  | Repo to clone               |
| `REPOMANCER_INTENT` | `default` | Intent to use when `--intent` isn't given |
| `REPOMANCER_AGENTS_REPO` | `https://github.com/SmartScrubs/agents-md.git` | Repo with the `AGENTS.md` files |
| `REPOMANCER_AUTO_UPDATE` | `yes` | Whether `repomancer` and `scry` [update themselves](#updates) |
| `SCRY_CLOSE_ON_EXIT` | `yes` | Whether `scry` closes the tab or pane when Claude Code exits |

To change them for good, edit `~/.config/repomancer/config` (the installer creates it with every line commented out):

```sh
REPOMANCER_ROOT="$HOME/code/workspaces"
```

For a single run, set an environment variable instead. It overrides the config file:

```sh
REPOMANCER_ROOT=~/scratch repomancer try-something
```

## Updates

`repomancer` and `scry` run from a clone of this repo (`~/tools/scrubs-ws-claude-workbench` when you installed with the one-liner), linked into `~/.local/bin`. At most once an hour, `repomancer` (when it opens a workspace) and `scry` (each time it shows its menu) fetch that clone. If there's a new version, they fast-forward the clone and restart, and `scry` shows what it updated to. A check that can't reach GitHub waits five seconds at most and is skipped until the next hour.

They only update a clone that can be fast-forwarded: one with no uncommitted changes to tracked files and no commits of its own. Otherwise, `repomancer --update` tells you why and what to run. To update right away, run `repomancer --update` or `scry --update`, or use **Check for updates now** in `scry`'s settings. To turn automatic updates off, set `REPOMANCER_AUTO_UPDATE="no"` in `~/.config/repomancer/config`.

## Cleaning up

Each workspace is an ordinary clone, so you remove one by deleting its folder once its branch is pushed or merged:

```sh
rm -rf ~/Documents/AIProjects/my-feature
```
