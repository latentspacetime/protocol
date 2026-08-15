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
| `shell/protocol.zsh` | Shell prompt, command wrappers, and shortcuts |
| `ghostty/` | Terminal defaults and live theme picker |
| `nvim/` | Neovim configuration and pinned plugin versions |
| `agent/` | Shared instructions, optional hooks, and reusable skills |
| `knowledge-vault/` | Content-neutral vault bootstrap and conventions |
| `pr-review/` | Secure design guidance for automated PR review systems |
| `install.zsh` | Non-destructive installer and link validator |
| `scripts/check.zsh` | Repository validation and privacy checks |

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

The installer is deliberately non-destructive. It creates missing links and
adds one marked source block to `~/.zshrc`, but refuses to replace regular
files or unrelated links. Existing configuration must be reviewed and moved
manually before installation.

Set the workspace root before sourcing the shell module when the default
`$HOME/Code` is not appropriate:

```zsh
export CODE_WORKSPACE="$HOME/path/to/code"
```

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
```

The check validates shell syntax, required files, executable scripts, broken
links, accidental absolute home paths, credential-like files, task identifiers,
and commit attribution trailers.

## License

MIT
