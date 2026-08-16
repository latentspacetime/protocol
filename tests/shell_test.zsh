#!/bin/zsh
# Behavior tests for the ugh friction-log command and scripts/doctor.zsh.
# Everything runs against an isolated temporary HOME so the tests never read
# or modify the real environment.

set -eu
root="${0:A:h:h}"
sandbox="$(mktemp -d)"
sandbox="${sandbox:A}"
trap 'rm -rf "$sandbox"' EXIT

typeset -i assertions=0

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    print -u2 -- "FAIL $label"
    print -u2 -- "  expected to contain: $needle"
    print -u2 -- "  actual: $haystack"
    exit 1
  fi
  (( assertions += 1 ))
}

assert_equal() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" != "$expected" ]]; then
    print -u2 -- "FAIL $label"
    print -u2 -- "  expected: $expected"
    print -u2 -- "  actual: $actual"
    exit 1
  fi
  (( assertions += 1 ))
}

assert_link() {
  local path="$1" target="$2" label="$3"
  if [[ ! -L "$path" || "${path:A}" != "${target:A}" ]]; then
    print -u2 -- "FAIL $label"
    print -u2 -- "  expected link: $path -> $target"
    print -u2 -- "  actual: ${path:A}"
    exit 1
  fi
  (( assertions += 1 ))
}

# The shell module targets interactive shells, where zsh hook arrays like
# precmd_functions may legitimately be unset; suspend nounset while sourcing.
export PROTOCOL_FRICTION_LOG="$sandbox/friction-log.md"
print -r -- "special-repo=68" > "$sandbox/repo-colors.conf"
export PROTOCOL_REPO_COLOR_CONFIG="$sandbox/repo-colors.conf"
set +u
source "$root/shell/protocol.zsh"
set -u

# Repository colors: the prompt API and Neovim's batch command use the same
# resolver, including environment-provided machine-local overrides.
protocol_repo_color special-repo
assert_equal "$REPLY" "68" "repo color resolver applies an override"
protocol_repo_color ordinary-repo
ordinary_repo_color="$REPLY"
resolved_colors=("${(@f)$(/bin/zsh "$root/shell/protocol.zsh" --repo-colors special-repo ordinary-repo)}")
assert_equal "$resolved_colors[1]" "68" "batch resolver applies the same override"
assert_equal "$resolved_colors[2]" "$ordinary_repo_color" "batch and prompt colors stay identical"
assert_equal "$PROTOCOL_ROOT" "$root" "protocol root is exported for Neovim"

for legacy_repo in -n 'slash\cname'; do
  legacy_hash=$(echo -n "$legacy_repo" | cksum | awk '{print $1}')
  legacy_color="${PROTOCOL_REPO_PALETTE[$((legacy_hash % ${#PROTOCOL_REPO_PALETTE[@]} + 1))]}"
  protocol_repo_color "$legacy_repo"
  assert_equal "$REPLY" "$legacy_color" "resolver preserves legacy echo hash for $legacy_repo"
done

print -r -- $'special-repo=99\nbroken=invalid' > "$PROTOCOL_REPO_COLOR_CONFIG"
reload_status=0
protocol_load_repo_colors 2>/dev/null || reload_status=$?
if (( reload_status == 0 )); then
  print -u2 -- "FAIL malformed color reload exits nonzero"
  exit 1
fi
(( assertions += 1 ))
protocol_repo_color special-repo
assert_equal "$REPLY" "68" "malformed reload preserves the last valid colors"
print -r -- "special-repo=68" > "$PROTOCOL_REPO_COLOR_CONFIG"

set -- --repo-colors should-remain
source "$root/shell/protocol.zsh"
assert_equal "$1" "--repo-colors" "sourcing does not consume caller positional arguments"
assert_equal "$2" "should-remain" "sourcing completes instead of entering batch mode"
set --

# Outside the workspace the prompt uses a plain default PS1, which
# PROTOCOL_PROMPT_FALLBACK replaces for machine-specific prompts.
saved_workspace="$CODE_WORKSPACE"
CODE_WORKSPACE="$sandbox/no-such-workspace"
cd "$sandbox"
protocol_repo_prompt
assert_equal "$PS1" "%1~ %% " "prompt outside the workspace uses the plain default"
PROTOCOL_PROMPT_FALLBACK="[test] %1~ %% "
protocol_repo_prompt
assert_equal "$PS1" "[test] %1~ %% " "PROTOCOL_PROMPT_FALLBACK overrides the fallback prompt"
unset PROTOCOL_PROMPT_FALLBACK
CODE_WORKSPACE="$saved_workspace"

assert_equal "${aliases[doctor]}" "$root/scripts/doctor.zsh" "doctor alias defaults to the module's own toolkit"

# ugh: first entry creates the log with a header and reports the count.
output=$(cd "$sandbox" && ugh first annoyance)
assert_contains "$output" "logged (1 total)" "ugh reports count after first entry"
assert_contains "$(cat "$PROTOCOL_FRICTION_LOG")" "# Friction Log" "log starts with header"
assert_contains "$(cat "$PROTOCOL_FRICTION_LOG")" "first annoyance" "entry records the message"
assert_contains "$(cat "$PROTOCOL_FRICTION_LOG")" "$sandbox:" "entry records the directory"

# ugh: messages are recorded verbatim, including shell-hostile characters.
output=$(cd "$sandbox" && ugh "quotes ' and | pipes and \$vars")
assert_contains "$(cat "$PROTOCOL_FRICTION_LOG")" "quotes ' and | pipes and \$vars" "special characters survive verbatim"

# ugh: inside a git repository the entry includes the branch name.
git init -q -b trunk "$sandbox/repo"
output=$(cd "$sandbox/repo" && ugh branch context test)
assert_contains "$(cat "$PROTOCOL_FRICTION_LOG")" "(trunk): branch context test" "entry records the git branch"

# ugh: no arguments lists the log location and recent entries.
output=$(ugh)
assert_contains "$output" "3 entries in $PROTOCOL_FRICTION_LOG" "listing reports the entry count"
assert_contains "$output" "branch context test" "listing shows recent entries"

# Sandboxed invocations override ZDOTDIR as well as HOME so the real user's
# zsh startup files never run inside the test, and XDG_CONFIG_HOME so the
# installer's git-ignore step can never touch the real global ignore file.
in_sandbox() {
  HOME="$sandbox" ZDOTDIR="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" "$@"
}

# doctor: on a machine without protocol installed it must fail honestly,
# naming the link problems, and exit nonzero.
doctor_status=0
doctor_output=$(in_sandbox "$root/scripts/doctor.zsh" 2>&1) || doctor_status=$?
if (( doctor_status == 0 )); then
  print -u2 -- "FAIL doctor exits nonzero on an uninstalled machine"
  exit 1
fi
(( assertions += 1 ))
assert_contains "$doctor_output" "installation incomplete" "doctor reports missing installation"
assert_contains "$doctor_output" "failure(s)" "doctor prints a failure summary"

# doctor: after installing into the sandbox HOME, the link check passes.
install_output=$(in_sandbox "$root/install.zsh")
assert_contains "$install_output" "protocol installed" "installer succeeds in sandbox HOME"
doctor_output=$(in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "installed links and shell integration" "doctor confirms links after install"

# Global git ignore: install appends every agent instruction pattern to the
# sandbox ignore file.
sandbox_ignore="$sandbox/.config/git/ignore"
for pattern in AGENTS.md CLAUDE.md .claude/; do
  assert_contains "$(cat "$sandbox_ignore")" "$pattern" "git ignore contains $pattern"
done

# Reinstalling must not duplicate the patterns.
install_output=$(in_sandbox "$root/install.zsh")
if (( $(grep -Fcx -- "AGENTS.md" "$sandbox_ignore") != 1 )); then
  print -u2 -- "FAIL reinstall duplicates git ignore lines"
  exit 1
fi
(( assertions += 1 ))

# A single missing pattern is restored without duplicating the others.
grep -Fvx -- "CLAUDE.md" "$sandbox_ignore" > "$sandbox_ignore.tmp"
mv "$sandbox_ignore.tmp" "$sandbox_ignore"
install_output=$(in_sandbox "$root/install.zsh")
assert_contains "$(cat "$sandbox_ignore")" "CLAUDE.md" "removed pattern is restored"
if (( $(grep -Fcx -- "AGENTS.md" "$sandbox_ignore") != 1 )); then
  print -u2 -- "FAIL partial repair duplicates git ignore lines"
  exit 1
fi
(( assertions += 1 ))

# A separate machine-specific config repository can own the live shell,
# Neovim, and Ghostty paths while protocol continues to own portable tooling.
overlay_home="$sandbox/overlay home"
overlay_root="$sandbox/local config"
mkdir -p "$overlay_home" "$overlay_root/nvim" "$overlay_root/ghostty" "$overlay_root/shell"
print -r -- "source ${(q)root}/shell/protocol.zsh" > "$overlay_root/shell/zshrc"

overlay_install_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" \
  XDG_CONFIG_HOME="$overlay_home/.config" PROTOCOL_CONFIG_ROOT="$overlay_root" \
  "$root/install.zsh")
assert_contains "$overlay_install_output" "protocol installed" "overlay installer succeeds"
assert_link "$overlay_home/.zshrc" "$overlay_root/shell/zshrc" "overlay owns zshrc"
assert_link "$overlay_home/.config/nvim" "$overlay_root/nvim" "overlay owns Neovim"
assert_link "$overlay_home/.config/ghostty" "$overlay_root/ghostty" "overlay owns Ghostty"

overlay_check_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" \
  XDG_CONFIG_HOME="$overlay_home/.config" PROTOCOL_CONFIG_ROOT="$overlay_root" \
  "$root/install.zsh" --check)
assert_contains "$overlay_check_output" "installation is valid" "overlay check succeeds"

overlay_doctor_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" \
  XDG_CONFIG_HOME="$overlay_home/.config" PROTOCOL_CONFIG_ROOT="$overlay_root" \
  "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$overlay_doctor_output" "installed links and shell integration" "doctor accepts overlay links"

print "shell tests passed ($assertions assertions)"
