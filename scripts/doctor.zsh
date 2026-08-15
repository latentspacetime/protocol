#!/bin/zsh
# doctor -- report whether this machine matches the protocol baseline:
# platform, required and optional tools, workspace layout, installed links.
# Observation only: doctor never installs anything and never boots the editor
# (a first Neovim boot clones plugins, a network side effect), so it is safe
# to run at any time. The requirement set mirrors "Requirements" in README.md.

set -u
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

protocol_root="${0:A:h:h}"
typeset -i failures=0 warnings=0

if [[ -t 1 ]]; then
  ok_color=$'\e[32m' warn_color=$'\e[33m' fail_color=$'\e[31m' reset=$'\e[0m'
else
  ok_color='' warn_color='' fail_color='' reset=''
fi

report() {
  # "outcome", not "status": $status is a read-only special variable in zsh.
  local outcome="$1" message="$2"
  case "$outcome" in
    ok)   print -r -- "${ok_color}ok${reset}    $message" ;;
    warn) print -r -- "${warn_color}warn${reset}  $message"; (( warnings += 1 )) ;;
    fail) print -r -- "${fail_color}fail${reset}  $message"; (( failures += 1 )) ;;
  esac
}

require_command() {
  local name="$1" purpose="$2"
  if command -v "$name" >/dev/null 2>&1; then
    report ok "$name found"
  else
    report fail "$name not found ($purpose)"
  fi
}

optional_command() {
  local name="$1" purpose="$2"
  if command -v "$name" >/dev/null 2>&1; then
    report ok "$name found"
  else
    report warn "$name not found (optional: $purpose)"
  fi
}

check_platform() {
  if [[ "$OSTYPE" == darwin* ]]; then
    report ok "macOS $(sw_vers -productVersion 2>/dev/null)"
  else
    report fail "platform is $OSTYPE (clipboard and terminal integration assume macOS)"
  fi
}

check_neovim() {
  if ! command -v nvim >/dev/null 2>&1; then
    report fail "nvim not found (editor configuration requires Neovim 0.9+)"
    return
  fi
  local version_line
  version_line=$(nvim --version 2>/dev/null | head -1)
  if [[ "$version_line" =~ 'v([0-9]+)\.([0-9]+)' ]]; then
    if (( match[1] > 0 || match[2] >= 9 )); then
      report ok "nvim ${version_line#NVIM } (0.9+ required)"
    else
      report fail "nvim too old: $version_line (0.9+ required)"
    fi
  else
    report fail "could not parse nvim version from: $version_line"
  fi
}

check_workspace() {
  local workspace="${CODE_WORKSPACE:-$HOME/Code}"
  if [[ -d "$workspace" ]]; then
    report ok "workspace $workspace"
  else
    report warn "workspace missing: $workspace (export CODE_WORKSPACE before sourcing shell/protocol.zsh)"
  fi
}

check_links() {
  local link_report
  if link_report=$("$protocol_root/install.zsh" --check 2>&1); then
    report ok "installed links and shell integration"
  else
    report fail "installation incomplete (run ./install.zsh)"
    print -r -- "$link_report" | sed 's/^/      /'
  fi
}

print -r -- "protocol doctor: $protocol_root"
print
check_platform
require_command git "version control"
check_neovim
require_command rg "search commands depend on ripgrep"
require_command perl "clipboard repair (cbfix)"
require_command pbcopy "clipboard repair (cbfix)"
require_command pbpaste "clipboard repair (cbfix)"
optional_command fzf "fuzzy pickers and theme selection"
optional_command zoxide "directory jumping"
optional_command claude "Claude Code launcher wrappers"
optional_command codex "Codex launcher wrapper"
optional_command opencode "oe shortcut"
check_workspace
check_links

print
if (( failures > 0 )); then
  print -r -- "doctor: $failures failure(s), $warnings warning(s)"
  exit 1
fi
print -r -- "doctor: healthy, $warnings warning(s)"
