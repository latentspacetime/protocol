# Agent-Guided Setup

Protocol is designed so that a coding agent can install it for you completely.
Open Claude Code, Codex, or OpenCode, point it at this repository, and say:

```text
Read SETUP.md and set up protocol for me.
```

The rest of this file is addressed to that agent.

## Instructions for the Agent

- Conduct the interview below in order, one question at a time. Offer the
  default, record the answer, and only then act on it.
- Every path in this repository is resolved from environment variables or from
  the user's answers. Never assume this machine matches the author's layout.
- The installer refuses to replace existing files and links. When it reports a
  conflict, show the user the existing file, explain the difference, and let
  the user decide whether to move it aside. Never delete or overwrite
  configuration without an explicit decision.
- Setup is complete when `doctor` exits zero, or when every remaining failure
  is one the user has explicitly declined to fix.

## Interview

### 1. Code workspace

Ask: "Where does your code live, or where should it? Protocol uses this
directory for repository-aware prompt colors and editor search scope."

Default: `$HOME/Code`.

If the answer differs from the default, add the export to `~/.zshrc` before
the protocol source block that the installer will append:

```zsh
export CODE_WORKSPACE="$HOME/path/to/code"
```

### 2. Repository location

Ask: "Where should the protocol repository itself live?"

Default: inside the workspace from question 1. Clone it there if this copy is
somewhere temporary. All installed links point into the clone, so it should
stay where it lands.

Ask: "Should the public protocol repository own the live shell, Neovim, and
Ghostty paths, or do you maintain those files in a separate local repository?"

Default: protocol owns the live paths. If the user chooses a separate source,
verify that it contains `shell/zshrc`, `nvim/`, and `ghostty/`, then export its
absolute path as `PROTOCOL_CONFIG_ROOT` before running the installer and
`doctor`. The installer links all three live paths to that root while keeping
agent instructions and skills linked to public protocol.

### 3. Neovim configuration

Ask: "Do you want protocol's Neovim configuration as your global editor
config?"

If `~/.config/nvim` already exists, present the choice honestly: keep the
existing configuration (the installer will report the conflict and skip the
link), or move it aside (`mv ~/.config/nvim ~/nvim-config-backup-<date>`) and
adopt protocol's. Existing plugin state in `~/.local/share/nvim` is unaffected
either way. The first launch after adoption installs pinned plugins from
`nvim/lazy-lock.json`, which needs network access.

### 4. Ghostty configuration

Ask: "Do you use Ghostty, and do you want protocol's terminal defaults and the
live `theme` picker?"

Same conflict rule as Neovim: an existing `~/.config/ghostty` is reported and
skipped, never replaced.

### 5. Agent harnesses

Ask: "Which coding agents do you use: Claude Code, Codex, OpenCode?"

The installer links the shared instructions and skills for all three; links
for harnesses that are not installed are harmless and become active if that
harness is added later. Note the answer so verification in step 8 checks the
harnesses the user actually runs.

### 6. Protocode

Ask: "Do you want `oe` to run a verified personal OpenCode distribution while
keeping official `opencode` available as a fallback?"

If yes, install Bun 1.3 or newer, clone the user's Protocode fork beside this
repository, configure `anomalyco/opencode` as its `upstream` remote, and check
out its `stable` branch. That branch is where the personal `protocode:`
commits live, on top of a pinned upstream tag; Protocol only records which
of those commits was built. Run `install.zsh` to install the static wrapper,
then follow the build and release-tag procedure in `README.md`. Verify that
`oe --version` uses the pinned build and `opencode --version` still uses the
official installation.

If no, the installed wrapper remains dormant and `doctor` reports Protocode as
an optional unconfigured component.

### 7. Global git ignore for agent instruction files

Explain: the installer adds `AGENTS.md`, `CLAUDE.md`, and `.claude/` to the
global git ignore, so repository-level agent files stay untracked by default
and committing one becomes a deliberate `git add -f`. Files a repository
already tracks are unaffected.

Ask: "Is that the behavior you want?"

If the user declines, remove those lines from the global ignore file after the
installer runs, and tell the user that `install.zsh --check` and `doctor` will
report them missing from then on.

### 8. Friction log location

Ask: "Where should the friction log live? `ugh <message>` appends timestamped
annoyances there so improvement work starts from evidence."

Default: `~/.local/state/protocol/friction-log.md`. A notes vault is a common
alternative. If the answer differs, add the export to `~/.zshrc` before the
protocol source block:

```zsh
export PROTOCOL_FRICTION_LOG="$HOME/notes/friction-log.md"
```

### 9. Knowledge vault

Ask: "Do you want a structured markdown knowledge vault initialized, and if
so, where?"

If yes, run `knowledge-vault/init.zsh` against the chosen directory and point
the user at `knowledge-vault/README.md` for the conventions it sets up. The
vault's content stays outside this repository permanently.

### 10. Screenshot directory

Ask: "Where should macOS screenshots be saved? The screenshot skill reads the
newest capture from this directory so you can show it to an agent without
dragging files."

The current setting comes from
`defaults read com.apple.screencapture location`. To change it:

```zsh
defaults write com.apple.screencapture location "$HOME/Documents/Screenshots"
killall SystemUIServer
```

### 11. Dotfile symlink folder

Ask: "Do you want a `symlinks/` folder in your workspace containing links to
configuration files that live outside any repository, such as harness settings
and the global git ignore?"

This makes those files reachable from editor fuzzy finders and note tools
without moving the originals. If yes, create the folder and add links for the
files the user names, for example:

```zsh
mkdir -p "$CODE_WORKSPACE/symlinks"
ln -s "$HOME/.config/git/ignore" "$CODE_WORKSPACE/symlinks/git-global-ignore"
```

## Installation

After the interview, from the repository root:

```zsh
./install.zsh
./install.zsh --check
```

Resolve any reported conflict with the user as described above, then rerun
both commands until `--check` passes or every remaining item is a decision the
user made.

## Verification

- `doctor` exits zero.
- A new shell shows a colored prompt inside a workspace repository, and `wt`,
  `gs`, `ugh`, `cbfix`, and `theme` are available.
- If Protocode was adopted: `oe --version` runs the pinned build, `opencode
  --version` remains available, and `doctor` confirms the source, pin, wrapper,
  and active build agree.
- Each harness from question 5 loads the shared instructions and lists the
  shared skills in a fresh session.
- If Neovim was adopted: `nvim` opens the workspace layout, and `:Rg` finds
  text across the workspace.

Report the result of each check to the user, including the ones that failed
and why, and log any remaining friction with `ugh`.
