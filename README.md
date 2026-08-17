# Protocol

Protocol is a portable development-environment toolkit for macOS. It keeps
shell shortcuts, Neovim configuration, coding-agent instructions, the
screenshot skill, a verified Protocode build pipeline, knowledge-vault conventions, and
pull-request review practices in one versioned repository.

The repository contains configuration only. It does not contain credentials,
machine-specific paths, private notes, project names, or organization-specific
automation.

## Contents

| Path | Purpose |
| --- | --- |
| `SETUP.md` | Interview a coding agent follows to install protocol for a user |
| `shell/protocol.zsh` | Shell prompt, command wrappers, and shortcuts |
| `ghostty/` | Terminal defaults and live theme picker |
| `nvim/` | Neovim configuration and pinned plugin versions |
| `agent/` | Shared instructions, optional hooks, and the screenshot skill |
| `knowledge-vault/` | Content-neutral vault bootstrap and conventions |
| `pr-review/` | Secure design guidance for automated PR review systems |
| `git-hooks/` | Global git hook dispatcher with agent-attribution stripping |
| `install.zsh` | Non-destructive installer and link validator |
| `bin/protocode` | Static launcher for the active verified Protocode build |
| `scripts/check.zsh` | Repository validation and privacy checks |
| `scripts/doctor.zsh` | Machine health report against the protocol baseline |
| `scripts/protocode-build.zsh` | Verified native build, atomic activation, pin, and retention pipeline |
| `scripts/protocode-promote.zsh` | Internal failure-recoverable artifact promotion state machine |
| `protocode.pin` | Upstream tag/commit provenance, Protocode release tag, source commit, and installed artifact digest |
| `tests/` | Behavior tests for shell commands and doctor |

## Requirements

- macOS
- zsh
- Git
- Neovim 0.10 or newer
- ripgrep
- Bun 1.3 or newer when using Protocode
- Optional: fzf, zoxide, Claude Code, Codex, and official OpenCode

## Install

Clone the repository anywhere, then run:

```zsh
./install.zsh
./install.zsh --check
```

The installer is deliberately non-destructive. It creates missing links,
installs the static Protocode wrapper, adds one marked source block to
`~/.zshrc`, and appends `AGENTS.md`, `CLAUDE.md`,
and `.claude/` to the global git ignore so repository-level agent instruction
files stay untracked by default; tracking one becomes a deliberate
`git add -f`, and files a repository already tracks are unaffected. It refuses
to replace regular files or unrelated links. Existing configuration must be
reviewed and moved manually before installation.

### Separate Live Configuration

Users who keep machine-specific shell, Neovim, and Ghostty files in a separate
repository can point the installer at that source while protocol continues to
own portable agent instructions, the screenshot skill, and tooling:

```zsh
export PROTOCOL_CONFIG_ROOT="$HOME/Code/protocol-local"
./install.zsh
./install.zsh --check
```

The external root must contain `shell/zshrc`, `nvim/`, and `ghostty/`. In this
mode the installer links `~/.zshrc`, `~/.config/nvim`, and
`~/.config/ghostty` to that root. The recommended arrangement is for the
external root to carry its own copy of `shell/protocol.zsh` and for its
`shell/zshrc` to source that copy, so live behavior has exactly one home and
this repository serves as the portable source the copy is synced against.
Export `PROTOCOL_TOOLKIT_ROOT` pointing at this repository's checkout so the
`doctor` alias resolves, and keep `PROTOCOL_CONFIG_ROOT` exported when running
`doctor` so it validates the selected source.

Set `PROTOCOL_AGENT_INSTRUCTIONS` or `PROTOCOL_SKILLS_ROOT` before running the
installer when another repository owns the canonical harness instructions or
skills. The installer validates those selected sources instead of requiring
the copies in this repository.

Set the workspace root before sourcing the shell module when the default
`$HOME/Code` is not appropriate:

```zsh
export CODE_WORKSPACE="$HOME/path/to/code"
```

## Neovim Workspace Picker

From any CORE terminal pane, press `<Leader>r` (`Space+r` with the default
Leader) to fuzzy-search the immediate folders under `CODE_WORKSPACE`. Press
Tab to copy the selected absolute path, or Enter to send a shell-escaped `cd`
command to the terminal pane that opened the picker. Use Enter while that pane
is at a shell prompt. Every entry uses the same Ghostty 256-color assignment as
the shell prompt. Explicit assignments live in `shell/repo-colors.conf`; the
prompt and picker both call `protocol_repo_color`, so the palette, hash, and
overrides have one owner.

## Warp LLM Popup

Inside Neovim, `<Leader>k` opens a small floating window for a quick LLM
query. Type a question and press Enter; the response streams in below a
divider with markdown rendering. Press `s` to cycle models, `m` for the menu,
and `b` to copy a code block from the response. Requests go to OpenRouter and
authenticate with the `OPENROUTER_API_KEY` environment variable; without the
key the popup reports that and sends nothing.

## Agent-Guided Setup

A coding agent can perform the entire installation, including every decision
above. Point Claude Code, Codex, or OpenCode at the repository and ask it to
follow [SETUP.md](SETUP.md), which contains the full interview: workspace
location, editor and terminal adoption, harness links, git ignore behavior,
friction-log routing, and verification with `doctor`.

## Shell Commands

Sourcing `shell/protocol.zsh` provides:

| Command | Purpose |
| --- | --- |
| `wt [name]` | List git worktrees, or jump to the first worktree matching a prefix |
| `gs [name]` | List branches, or switch to the first branch matching a prefix |
| `gpo` | `git pull origin` |
| `cbfix` | Repair clipboard text that terminal agents hard-wrapped |
| `ugh [message]` | Append a timestamped entry to the friction log; without a message, show recent entries |
| `doctor` | Report machine health against the protocol baseline |
| `theme` | Live Ghostty theme picker |
| `claude` / `codex` / `ci` | Coding-agent launchers with session color and shorthand flags |
| `oe [args]` | Launch the active verified Protocode build with `--auto` and forward all arguments |

## Friction Log

Workflow improvements should start from evidence, not recall. The moment
something feels slow or awkward, record it:

```zsh
ugh renaming a worktree still takes four commands
```

Each entry captures the timestamp, directory, and git branch in a plain
markdown file. Run `ugh` with no arguments to review recent entries. The log
lives at `~/.local/state/protocol/friction-log.md` by default; point it
somewhere else (for example, into a notes vault) before sourcing the shell
module:

```zsh
export PROTOCOL_FRICTION_LOG="$HOME/notes/friction-log.md"
```

## Doctor

`doctor` answers "does this machine match the baseline?" in one run: platform,
required and optional tools, Neovim version, workspace root, every installed
link, and any configured Protocode source, pin, release tag, wrapper, and
active build. It only observes; it never installs or repairs. Protocode is
optional when no source or build exists; a partial or inconsistent setup is a
failure. `doctor` exits nonzero when anything required is missing, so it also
serves as an acceptance check after installation.


## Validate

```zsh
./scripts/check.zsh
./tests/shell_test.zsh
./tests/nvim_test.zsh
doctor
```

The check validates shell syntax, required files, executable scripts, broken
links, accidental absolute home paths, credential-like files, task identifiers,
and commit attribution trailers. The tests exercise the shell commands, doctor,
and Neovim behavior in isolated temporary environments. All run in CI on every
pull request; `doctor` validates the machine rather than the repository.

## License

MIT
