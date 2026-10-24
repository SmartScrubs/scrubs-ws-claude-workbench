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
5. Copies an `AGENTS.md` for the chosen [intent](#intents) into the workspace, so Claude starts out knowing what kind of work it's there for.
6. Runs `claude --name "ws+my-feature"`, so the session is easy to find in `/resume` and in the terminal title.

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

`scry` lists every workspace in your workspace folder, newest first. For each one it shows the branch, the intent, how long ago you last worked on it, and whether it has uncommitted or unpushed changes. A side panel previews the highlighted workspace's `git status` and recent commits.

```sh
scry           # interactive menu
scry --list    # just print the list
```

| Key | Action |
|-----|--------|
| type | filter the list |
| <kbd>Enter</kbd> | open the workspace in a new iTerm2 tab (in a new window if iTerm2 has none open). It runs `repomancer <workspace>`, so the Claude session resumes |
| <kbd>⌃W</kbd> | open it in a new iTerm2 window instead |
| <kbd>⌃N</kbd> or **+ New workspace…** | asks for a branch, an optional base branch and an intent, then runs `repomancer` in a new tab |
| <kbd>⌃S</kbd> or **⚙ Settings…** | change the workspace folder, default intent or repos (each one checked before saving), or open the config file in your editor |
| <kbd>Esc</kbd> | quit |

The first time `scry` opens a tab, macOS asks whether your terminal may control iTerm2. Allow it. Without fzf, `scry` shows a numbered menu with the same options.

## Setup (new Mac)

`install.sh` sets up everything the workbench needs, then walks you through signing in. It skips anything already installed or signed in, so it's safe to re-run.

| What | How it's installed |
|------|--------------------|
| Homebrew | official installer, plus `brew shellenv` in `~/.zprofile` |
| Oh My Zsh | official installer, run so it never replaces an existing `~/.zshrc`. Set to update itself automatically, without the "update now?" question when a terminal opens |
| git, GitHub CLI, AWS CLI, uv, fzf | `brew install` |
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
| GitHub | `gh auth login` in your browser, then `gh auth setup-git` so git can clone private SmartScrubs repos over HTTPS. Then it checks you can reach `SmartScrubs/scrubs` |
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
- `WORKBENCH_DIR` sets where the workbench repo is cloned when the script runs from a URL instead of a checkout. The default is `~/tools/scrubs-ws-claude-workbench`.

At the end it checks every MCP server Claude Code can see (`claude mcp list`) and lists any that need signing in or failed to connect. Sign in to the ones you need from Claude Code with `/mcp`, then open a new terminal.

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

To change them for good, edit `~/.config/repomancer/config` (the installer creates it with every line commented out):

```sh
REPOMANCER_ROOT="$HOME/code/workspaces"
```

For a single run, set an environment variable instead. It overrides the config file:

```sh
REPOMANCER_ROOT=~/scratch repomancer try-something
```

## Cleaning up

Each workspace is an ordinary clone, so you remove one by deleting its folder once its branch is pushed or merged:

```sh
rm -rf ~/Documents/AIProjects/my-feature
```
