#!/bin/zsh

set -eu
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

mode="${1:-install}"
if [[ "$mode" != "install" && "$mode" != "--check" ]]; then
  print -u2 "usage: $0 [--check]"
  exit 2
fi

protocol_root="${0:A:h}"
shell_source="source \"$protocol_root/shell/protocol.zsh\""
shell_start="# >>> protocol >>>"
shell_end="# <<< protocol <<<"

ensure_link() {
  local source_path="$1"
  local target_path="$2"

  if [[ -L "$target_path" && "${target_path:A}" == "${source_path:A}" ]]; then
    return
  fi

  if [[ -e "$target_path" || -L "$target_path" ]]; then
    print -u2 "refusing to replace existing path: $target_path"
    return 1
  fi

  if [[ "$mode" == "--check" ]]; then
    print -u2 "missing link: $target_path -> $source_path"
    return 1
  fi

  mkdir -p "${target_path:h}"
  ln -s "$source_path" "$target_path"
}

ensure_shell_source() {
  local zshrc="$HOME/.zshrc"

  if [[ -f "$zshrc" ]] && grep -Fqx "$shell_source" "$zshrc"; then
    return
  fi

  if [[ "$mode" == "--check" ]]; then
    print -u2 "missing protocol source line in $zshrc"
    return 1
  fi

  {
    print
    print -r -- "$shell_start"
    print -r -- "$shell_source"
    print -r -- "$shell_end"
  } >> "$zshrc"
}

# Repo-level agent instruction files stay untracked by default; committing one
# becomes a deliberate `git add -f`. A global ignore never affects files a
# repository already tracks.
agent_ignore_lines=(AGENTS.md CLAUDE.md .claude/)

ensure_git_ignore() {
  local ignore_file
  ignore_file="$(git config --global --path --get core.excludesFile 2>/dev/null || true)"
  [[ -n "$ignore_file" ]] || ignore_file="${XDG_CONFIG_HOME:-$HOME/.config}/git/ignore"

  local -a missing_lines=()
  local line
  for line in "${agent_ignore_lines[@]}"; do
    if [[ -f "$ignore_file" ]] && grep -Fqx -- "$line" "$ignore_file"; then
      continue
    fi
    missing_lines+=("$line")
  done

  if (( ${#missing_lines} == 0 )); then
    return
  fi

  if [[ "$mode" == "--check" ]]; then
    print -u2 "missing agent ignore line(s) in $ignore_file: ${missing_lines[*]}"
    return 1
  fi

  mkdir -p "${ignore_file:h}"
  print -rl -- "${missing_lines[@]}" >> "$ignore_file"
}

ensure_shell_source
ensure_git_ignore
ensure_link "$protocol_root/nvim" "$HOME/.config/nvim"
ensure_link "$protocol_root/ghostty" "$HOME/.config/ghostty"
ensure_link "$protocol_root/agent/AGENTS.md" "$HOME/.claude/CLAUDE.md"
ensure_link "$protocol_root/agent/AGENTS.md" "$HOME/.codex/AGENTS.md"
ensure_link "$protocol_root/agent/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"

for skill in "$protocol_root"/agent/skills/*(/N); do
  [[ -f "$skill/SKILL.md" ]] || continue
  ensure_link "$skill" "$HOME/.claude/skills/${skill:t}"
  ensure_link "$skill" "$HOME/.agents/skills/${skill:t}"
done

if [[ "$mode" == "--check" ]]; then
  print "protocol installation is valid"
else
  print "protocol installed"
fi
