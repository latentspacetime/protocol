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
    report fail "nvim not found (editor configuration requires Neovim 0.10+)"
    return
  fi
  local version_line
  version_line=$(nvim --version 2>/dev/null | head -1)
  if [[ "$version_line" =~ 'v([0-9]+)\.([0-9]+)' ]]; then
    if (( match[1] > 0 || match[2] >= 10 )); then
      report ok "nvim ${version_line#NVIM } (0.10+ required)"
    else
      report fail "nvim too old: $version_line (0.10+ required)"
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

check_bun() {
  if ! command -v bun >/dev/null 2>&1; then
    report fail "bun not found (Protocode requires Bun 1.3+)"
    return 1
  fi

  local version
  local -a parts
  version=$(bun --version 2>/dev/null)
  parts=("${(@s:.:)version}")
  if (( ${parts[1]:-0} > 1 || (${parts[1]:-0} == 1 && ${parts[2]:-0} >= 3) )); then
    report ok "bun $version (1.3+ required for Protocode)"
    return
  fi
  report fail "bun too old: $version (Protocode requires 1.3+)"
  return 1
}

read_protocode_pin() {
  local pin_file="$1" line key value
  local -A seen
  UPSTREAM_TAG='' UPSTREAM_COMMIT='' PROTOCODE_TAG='' COMMIT='' ARTIFACT_SHA256='' BUILT=''
  PROTOCODE_PIN_ERROR=''

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != *=* ]]; then
      PROTOCODE_PIN_ERROR="malformed line in $pin_file"
      return 1
    fi
    key="${line%%=*}"
    value="${line#*=}"
    if [[ -n "${seen[$key]:-}" ]]; then
      PROTOCODE_PIN_ERROR="duplicate $key in $pin_file"
      return 1
    fi
    seen[$key]=1
    case "$key" in
      UPSTREAM_TAG) UPSTREAM_TAG="$value" ;;
      UPSTREAM_COMMIT) UPSTREAM_COMMIT="$value" ;;
      PROTOCODE_TAG) PROTOCODE_TAG="$value" ;;
      COMMIT) COMMIT="$value" ;;
      ARTIFACT_SHA256) ARTIFACT_SHA256="$value" ;;
      BUILT) BUILT="$value" ;;
      *)
        PROTOCODE_PIN_ERROR="unknown key $key in $pin_file"
        return 1
        ;;
    esac
  done < "$pin_file"

  if [[ ! "$UPSTREAM_TAG" =~ '^v[0-9]+\.[0-9]+\.[0-9]+$' ||
        ! "$UPSTREAM_COMMIT" =~ '^[0-9a-f]{40}$' ||
        ! "$PROTOCODE_TAG" =~ '^protocode-[0-9]+\.[0-9]+\.[0-9]+-r[0-9]+$' ||
        ! "$COMMIT" =~ '^[0-9a-f]{40}$' ||
        ! "$ARTIFACT_SHA256" =~ '^[0-9a-f]{64}$' ||
        ! "$BUILT" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' ]]; then
    PROTOCODE_PIN_ERROR="invalid values in $pin_file"
    return 1
  fi
  local upstream_version="${UPSTREAM_TAG#v}"
  local release_version="${PROTOCODE_TAG#protocode-}"
  release_version="${release_version%-r*}"
  if [[ "$release_version" != "$upstream_version" ]]; then
    PROTOCODE_PIN_ERROR="Protocode and upstream versions differ in $pin_file"
    return 1
  fi
}

check_protocode() {
  local source_root="${PROTOCODE_SOURCE_ROOT:-${CODE_WORKSPACE:-$HOME/Code}/protocode}"
  local install_root="${PROTOCODE_INSTALL_ROOT:-$HOME/.local/share/protocode}"
  local wrapper="${PROTOCODE_BIN:-$HOME/.local/bin/protocode}"
  local pin_file="${PROTOCODE_PIN_FILE:-$protocol_root/protocode.pin}"
  local current="$install_root/current"

  if [[ ! -d "$source_root/.git" && ! -f "$source_root/.git" && ! -e "$current" && ! -L "$current" ]]; then
    report warn "Protocode not configured (optional; see README.md)"
    return
  fi

  check_bun || true

  if [[ ! -f "$pin_file" ]]; then
    report fail "Protocode pin missing: $pin_file"
    return
  fi
  if ! read_protocode_pin "$pin_file"; then
    report fail "$PROTOCODE_PIN_ERROR"
    return
  fi
  report ok "Protocode pin $PROTOCODE_TAG"

  if [[ ! -d "$source_root/.git" && ! -f "$source_root/.git" ]]; then
    report fail "Protocode source clone missing: $source_root"
  else
    local branch head upstream_url
    branch=$(git -C "$source_root" branch --show-current 2>/dev/null)
    head=$(git -C "$source_root" rev-parse HEAD 2>/dev/null)
    upstream_url=$(git -C "$source_root" remote get-url upstream 2>/dev/null)
    case "$upstream_url" in
      https://github.com/anomalyco/opencode|https://github.com/anomalyco/opencode.git|git@github.com:anomalyco/opencode.git)
        report ok "Protocode upstream remote is anomalyco/opencode"
        ;;
      *) report fail "Protocode upstream remote is invalid: ${upstream_url:-missing}" ;;
    esac
    if [[ "$branch" == "stable" ]]; then
      report ok "Protocode source branch stable"
    else
      report fail "Protocode source branch is ${branch:-detached HEAD}; expected stable"
    fi
    if [[ -z "$(git -C "$source_root" status --porcelain 2>/dev/null)" ]]; then
      report ok "Protocode source worktree clean"
    else
      report fail "Protocode source worktree has changes"
    fi
    if [[ "$head" == "$COMMIT" ]]; then
      report ok "Protocode source matches pinned commit"
    else
      report fail "Protocode source $head does not match pinned commit $COMMIT"
    fi
    local local_upstream_commit trusted_upstream_commit
    local_upstream_commit=$(git -C "$source_root" rev-parse "$UPSTREAM_TAG^{}" 2>/dev/null)
    trusted_upstream_commit=$(git -C "$source_root" rev-parse "refs/protocode/upstream-tags/$UPSTREAM_TAG^{}" 2>/dev/null)
    if [[ "$local_upstream_commit" == "$UPSTREAM_COMMIT" && "$trusted_upstream_commit" == "$UPSTREAM_COMMIT" ]]; then
      report ok "Protocode upstream tag matches fetched provenance"
    else
      report fail "Protocode upstream tag provenance does not match pin"
    fi
    if git -C "$source_root" merge-base --is-ancestor "$UPSTREAM_COMMIT" "$COMMIT" 2>/dev/null; then
      report ok "Protocode commit descends from $UPSTREAM_TAG ($UPSTREAM_COMMIT)"
    else
      report fail "Protocode commit does not descend from $UPSTREAM_TAG"
    fi
    if [[ "$(git -C "$source_root" rev-parse "$PROTOCODE_TAG^{}" 2>/dev/null)" == "$COMMIT" ]]; then
      report ok "Protocode release tag matches pinned commit"
    else
      report fail "Protocode release tag does not match pinned commit"
    fi
  fi

  if [[ ! -x "$wrapper" ]]; then
    report fail "Protocode wrapper missing or not executable: $wrapper"
  elif /bin/zsh -n "$wrapper"; then
    report ok "Protocode wrapper healthy"
  else
    report fail "Protocode wrapper has invalid zsh syntax: $wrapper"
  fi

  if [[ ! -L "$current" ]]; then
    report fail "Protocode current link missing: $current"
  elif [[ "${current:A}" != "${install_root:A}/builds/$COMMIT" ]]; then
    report fail "Protocode current build does not match pinned commit"
  elif [[ ! -x "$current/protocode" ]]; then
    report fail "Protocode current executable missing"
  else
    local installed_sha
    installed_sha=$(/usr/bin/shasum -a 256 "$current/protocode")
    installed_sha="${installed_sha%% *}"
    if [[ "$installed_sha" == "$ARTIFACT_SHA256" ]]; then
      report ok "Protocode current build and artifact digest match pin"
    else
      report fail "Protocode current artifact digest does not match pin"
    fi
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
optional_command opencode "official OpenCode fallback"
check_protocode
check_workspace
check_links

print
if (( failures > 0 )); then
  print -r -- "doctor: $failures failure(s), $warnings warning(s)"
  exit 1
fi
print -r -- "doctor: healthy, $warnings warning(s)"
