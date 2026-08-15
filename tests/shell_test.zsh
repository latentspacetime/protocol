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

# The shell module targets interactive shells, where zsh hook arrays like
# precmd_functions may legitimately be unset; suspend nounset while sourcing.
export PROTOCOL_FRICTION_LOG="$sandbox/friction-log.md"
set +u
source "$root/shell/protocol.zsh"
set -u

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
# zsh startup files never run inside the test.
in_sandbox() {
  HOME="$sandbox" ZDOTDIR="$sandbox" "$@"
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

print "shell tests passed ($assertions assertions)"
