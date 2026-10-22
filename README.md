# ws — Claude Code workspace launcher

`ws` gives you a fresh clone of [SmartScrubs/scrubs](https://github.com/SmartScrubs/scrubs) on a new branch, then opens Claude Code in it.

```sh
ws my-feature            # branch from the repo's default branch (currently `zenbu`)
ws my-feature main       # branch from `main` instead
```

What it does:

1. Checks that the branch names are valid, that the base branch exists on GitHub, and that `claude` is on your `PATH`.
2. Clones the repo into `~/Documents/AIProjects/my-feature`, wherever you run `ws` from (a `/` in the branch name becomes `-`, so `feature/x` goes in `feature-x/`). See [Configuration](#configuration) to use a different folder.
3. Creates the branch from the base branch (the second argument, or the repo's default branch if you leave it out) and switches to it. If the branch already exists on `origin`, it checks that one out instead and ignores the base branch.
4. Points the branch at `origin/<branch>` and sets `push.autoSetupRemote`, so a plain `git push` works the first time.
5. Runs `claude --name "ws+my-feature"`, so the session is easy to find in `/resume` and in the terminal title.

If `~/Documents/AIProjects/my-feature` already exists, `ws my-feature` reopens it instead. It resumes the most recent Claude session in that folder (`claude --continue`), or starts a new `ws+my-feature` session if there isn't one. The base branch argument is ignored in that case.

## Setup (new Mac)

`install.sh` sets up everything the workbench needs, then walks you through signing in. It skips anything already installed or signed in, so it's safe to re-run.

| What | How it's installed |
|------|--------------------|
| Homebrew | official installer, plus `brew shellenv` in `~/.zprofile` |
| git, GitHub CLI, AWS CLI, uv | `brew install` |
| Maven | `brew install maven` |
| Java 11, 21, 25 | `brew install --cask temurin@<version>`, unless a JDK of that version is already installed |
| iTerm2, VS Code | `brew install --cask` (plus the `code` command) |
| Claude Code | official installer (`curl -fsSL https://claude.ai/install.sh \| bash`) |
| Claude Code plugins: sentry, postman, superpowers, comfy-cloud | `claude plugin install` (from `claude-plugins-official` and `comfy-skills`) |
| AWS skills and AWS MCP server for Claude Code | `aws configure agent-toolkit --yes` |
| Claude Code extension for VS Code | `code --install-extension anthropic.claude-code` |
| `ws` command | symlink in `~/.local/bin`, which is added to `PATH` in `~/.zshrc` |

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

### Java versions

The installer adds this to `~/.zshrc`:

- `JAVA_HOME` defaults to Java 25. Set `JAVA_DEFAULT=21 ./install.sh` before the first install to choose a different default.
- `jdk 11`, `jdk 21` or `jdk 25` switches the current terminal to that version. `java` and `mvn` both follow it.

```sh
jdk 11
mvn clean install
```

### Manual setup

If you already have the tools, you only need `ws` on your `PATH`:

```sh
ln -s "$PWD/ws" ~/.local/bin/ws
```

## Configuration

| Setting   | Default                                      | Purpose                     |
|-----------|----------------------------------------------|-----------------------------|
| `WS_ROOT` | `~/Documents/AIProjects`                     | Folder where workspaces go  |
| `WS_REPO` | `https://github.com/SmartScrubs/scrubs.git`  | Repo to clone               |

To change them for good, edit `~/.config/ws/config` (the installer creates it with every line commented out):

```sh
WS_ROOT="$HOME/code/workspaces"
```

For a single run, set an environment variable instead. It overrides the config file:

```sh
WS_ROOT=~/scratch ws try-something
```

## Cleaning up

Each workspace is an ordinary clone, so you remove one by deleting its folder once its branch is pushed or merged:

```sh
rm -rf ~/Documents/AIProjects/my-feature
```
