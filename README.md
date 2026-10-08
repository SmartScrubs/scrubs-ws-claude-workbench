# ws — Claude Code workspace launcher

`ws` gives you a fresh clone of [SmartScrubs/scrubs](https://github.com/SmartScrubs/scrubs) on a new branch, then opens Claude Code in it.

```sh
ws my-feature
```

What it does:

1. Checks that the branch name is valid and that `claude` is on your `PATH`.
2. Clones the repo into `./my-feature` (a `/` in the branch name becomes `-`, so `feature/x` goes in `feature-x/`). It stops if that folder already exists.
3. Creates the branch and switches to it. If the branch already exists on `origin`, it checks that one out instead.
4. Points the branch at `origin/<branch>` and sets `push.autoSetupRemote`, so a plain `git push` works the first time.
5. Runs `claude --name "ws+my-feature"`, so the session is easy to find in `/resume` and in the terminal title.

## Requirements

- macOS or Linux with `bash` and `git`
- [Claude Code](https://claude.com/claude-code), installed and signed in (`claude` on your `PATH`)
- Access to `SmartScrubs/scrubs`: the clone uses HTTPS, so you need a credential helper or `gh auth login`

## Setup

```sh
git clone <this-repo-url> ~/tools/claudeworkbenchscript
cd ~/tools/claudeworkbenchscript
chmod +x ws

# Put it on your PATH (choose one)
ln -s "$PWD/ws" /usr/local/bin/ws        # system-wide (may need sudo)
ln -s "$PWD/ws" ~/.local/bin/ws          # per-user, if ~/.local/bin is on PATH
```

Optional: choose where workspaces go by adding this to `~/.zshrc`:

```sh
export WS_ROOT="$HOME/work"
```

## Configuration

| Variable  | Default                                      | Purpose                         |
|-----------|----------------------------------------------|---------------------------------|
| `WS_ROOT` | current directory                            | Parent folder for new workspaces |
| `WS_REPO` | `https://github.com/SmartScrubs/scrubs.git`  | Repo to clone                   |

## Cleaning up

Each workspace is an ordinary clone, so you remove one by deleting its folder once its branch is pushed or merged:

```sh
rm -rf "$WS_ROOT/my-feature"
```
