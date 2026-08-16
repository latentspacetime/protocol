# Protocol

Protocol is a portable development-environment toolkit for macOS. It keeps
shell shortcuts, Neovim configuration, coding-agent instructions, reusable
skills, knowledge-vault conventions, and pull-request review practices in one
versioned repository.

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
| `agent/` | Shared instructions, optional hooks, and reusable skills |
| `knowledge-vault/` | Content-neutral vault bootstrap and conventions |
| `pr-review/` | Secure design guidance for automated PR review systems |
| `install.zsh` | Non-destructive installer and link validator |
| `scripts/check.zsh` | Repository validation and privacy checks |
| `scripts/doctor.zsh` | Machine health report against the protocol baseline |
| `tests/` | Behavior tests for shell commands and doctor |

## Requirements

- macOS
- zsh
- Git
- Neovim 0.9 or newer
- ripgrep
- Optional: fzf, zoxide, Claude Code, Codex, and OpenCode

## Install

Clone the repository anywhere, then run:

```zsh
./install.zsh
./install.zsh --check
```

The installer is deliberately non-destructive. It creates missing links, adds
one marked source block to `~/.zshrc`, and appends `AGENTS.md`, `CLAUDE.md`,
and `.claude/` to the global git ignore so repository-level agent instruction
files stay untracked by default; tracking one becomes a deliberate
`git add -f`, and files a repository already tracks are unaffected. It refuses
to replace regular files or unrelated links. Existing configuration must be
reviewed and moved manually before installation.

Set the workspace root before sourcing the shell module when the default
`$HOME/Code` is not appropriate:

```zsh
export CODE_WORKSPACE="$HOME/path/to/code"
```

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
| `claude` / `codex` / `ci` / `oe` | Coding-agent launchers with session color and shorthand flags |

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
required and optional tools, Neovim version, workspace root, and every
installed link. It only observes; it never installs or repairs. It exits
nonzero when anything required is missing, so it also serves as an acceptance
check after running `install.zsh` on a new machine.

## Safety Model

- Secrets and local overrides stay in untracked local files.
- Install operations are idempotent and fail on conflicts.
- Agent instructions remain generic; repository-local instructions take
  precedence for project-specific behavior.
- Automated reviewers are read-only by default. Any fixer must separate an
  uncredentialed model job from the credentialed job that applies a reviewed
  patch.
- Knowledge-vault content remains outside this repository.

## Validate

```zsh
./scripts/check.zsh
./tests/shell_test.zsh
doctor
```

The check validates shell syntax, required files, executable scripts, broken
links, accidental absolute home paths, credential-like files, task identifiers,
and commit attribution trailers. The tests exercise the shell commands and
doctor in an isolated temporary home. Both run in CI on every pull request;
`doctor` validates the machine rather than the repository.

## License

MIT
