#!/bin/zsh
# Behavior tests for the ugh friction-log command and scripts/doctor.zsh.
# Everything runs against an isolated temporary HOME so the tests never read
# or modify the real environment.

set -eu
root="${0:A:h:h}"
sandbox="$(mktemp -d)"
sandbox="${sandbox:A}"
trap 'rm -rf "$sandbox"' EXIT
unset PROTOCOL_CONFIG_ROOT PROTOCOL_AGENT_INSTRUCTIONS PROTOCOL_SKILLS_ROOT

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

assert_same_file() {
  local actual="$1" expected="$2" label="$3"
  if [[ ! -x "$actual" ]] || ! cmp -s "$actual" "$expected"; then
    print -u2 -- "FAIL $label"
    print -u2 -- "  expected executable copy: $actual == $expected"
    exit 1
  fi
  (( assertions += 1 ))
}

assert_absent() {
  local path="$1" label="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    print -u2 -- "FAIL $label"
    print -u2 -- "  expected absent: $path"
    exit 1
  fi
  (( assertions += 1 ))
}

assert_executable() {
  local path="$1" label="$2"
  if [[ ! -x "$path" ]]; then
    print -u2 -- "FAIL $label"
    print -u2 -- "  expected executable: $path"
    exit 1
  fi
  (( assertions += 1 ))
}

# The shell module targets interactive shells, where zsh hook arrays like
# precmd_functions may legitimately be unset; suspend nounset while sourcing.
export PROTOCOL_FRICTION_LOG="$sandbox/friction-log.md"
print -r -- "special-repo=68" > "$sandbox/repo-colors.conf"
export PROTOCOL_REPO_COLOR_CONFIG="$sandbox/repo-colors.conf"
unset PROTOCOL_PROMPT_FALLBACK
unset PROTOCOL_TOOLKIT_ROOT
alias oe='opencode --auto'
set +u
source "$root/shell/protocol.zsh"
set -u
assert_equal "$(whence -w oe)" "oe: function" "sourcing replaces the legacy oe alias"

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

# Claude session helpers: symlink cwd keys match realpath, and /color stubs
# are deleted without touching titled or real-prompt transcripts.
claude_sandbox="$sandbox/claude-sessions"
mkdir -p "$claude_sandbox/real/dir"
ln -s "$claude_sandbox/real/dir" "$claude_sandbox/link"
saved_claude_config="${CLAUDE_CONFIG_DIR-}"
export CLAUDE_CONFIG_DIR="$claude_sandbox/config"
assert_equal "$(protocol_claude_project_key "$claude_sandbox/link")" \
  "$(protocol_claude_project_key "$claude_sandbox/real/dir")" \
  "claude project key follows realpath through a symlink"
sid="11111111-1111-1111-1111-111111111111"
assert_equal "$(protocol_claude_session_path "$sid" "$claude_sandbox/link")" \
  "$CLAUDE_CONFIG_DIR/projects/$(protocol_claude_project_key "$claude_sandbox/real/dir")/${sid}.jsonl" \
  "claude session path uses the canonical project key"

stub="$claude_sandbox/stub.jsonl"
print -r -- '{"type":"agent-color","agentColor":"red","sessionId":"x"}' > "$stub"
print -r -- '{"type":"user","message":{"content":"<command-name>/color</command-name>"},"isMeta":false}' >> "$stub"
if protocol_claude_session_is_stub "$stub"; then
  (( assertions += 1 ))
else
  print -u2 -- "FAIL color-only transcript is a stub"
  exit 1
fi

titled="$claude_sandbox/titled.jsonl"
print -r -- '{"type":"agent-color","agentColor":"red","sessionId":"x"}' > "$titled"
print -r -- '{"type":"custom-title","customTitle":"Real work"}' >> "$titled"
if protocol_claude_session_is_stub "$titled"; then
  print -u2 -- "FAIL titled transcript is not a stub"
  exit 1
fi
(( assertions += 1 ))

real_prompt="$claude_sandbox/real.jsonl"
print -r -- '{"type":"agent-color","agentColor":"red","sessionId":"x"}' > "$real_prompt"
print -r -- '{"type":"user","message":{"content":"please fix resume"}}' >> "$real_prompt"
if protocol_claude_session_is_stub "$real_prompt"; then
  print -u2 -- "FAIL real-prompt transcript is not a stub"
  exit 1
fi
(( assertions += 1 ))

protocol_reap_claude_color_stub "$stub"
protocol_reap_claude_color_stub "$titled"
protocol_reap_claude_color_stub "$real_prompt"
assert_absent "$stub" "color stub is deleted"
if [[ ! -f "$titled" ]]; then
  print -u2 -- "FAIL titled transcript was deleted"
  exit 1
fi
(( assertions += 1 ))
if [[ ! -f "$real_prompt" ]]; then
  print -u2 -- "FAIL real-prompt transcript was deleted"
  exit 1
fi
(( assertions += 1 ))

mkdir -p "$CLAUDE_CONFIG_DIR/projects/proj"
cp "$real_prompt" "$CLAUDE_CONFIG_DIR/projects/proj/keep.jsonl"
print -r -- '{"type":"agent-color","agentColor":"blue","sessionId":"y"}' > "$CLAUDE_CONFIG_DIR/projects/proj/drop.jsonl"
print -r -- '{"type":"user","message":{"content":"<command-name>/color</command-name>"}}' >> "$CLAUDE_CONFIG_DIR/projects/proj/drop.jsonl"
protocol_reap_claude_color_stubs
assert_absent "$CLAUDE_CONFIG_DIR/projects/proj/drop.jsonl" "bulk reaper deletes color stubs"
if [[ ! -f "$CLAUDE_CONFIG_DIR/projects/proj/keep.jsonl" ]]; then
  print -u2 -- "FAIL bulk reaper deleted a real transcript"
  exit 1
fi
(( assertions += 1 ))
if [[ -n "$saved_claude_config" ]]; then
  export CLAUDE_CONFIG_DIR="$saved_claude_config"
else
  unset CLAUDE_CONFIG_DIR
fi

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

# oe: the shell function adds --auto, preserves arguments, and propagates the
# launcher's status without falling back to the official OpenCode command.
fake_launcher="$sandbox/fake-protocode"
launcher_capture="$sandbox/launcher-arguments"
{
  print '#!/bin/zsh -f'
  print 'print -rl -- "$@" > "$PROTOCODE_CAPTURE"'
  print 'exit "${PROTOCODE_EXIT:-0}"'
} > "$fake_launcher"
chmod 755 "$fake_launcher"

PROTOCODE_BIN="$fake_launcher" PROTOCODE_CAPTURE="$launcher_capture" oe "argument with spaces" '$literal'
launcher_args=("${(@f)$(cat "$launcher_capture")}")
assert_equal "$launcher_args[1]" "--auto" "oe enables auto permission mode"
assert_equal "$launcher_args[2]" "argument with spaces" "oe preserves a spaced argument"
assert_equal "$launcher_args[3]" '$literal' "oe preserves shell metacharacters"

launcher_status=0
PROTOCODE_BIN="$fake_launcher" PROTOCODE_CAPTURE="$launcher_capture" PROTOCODE_EXIT=23 oe >/dev/null 2>&1 || launcher_status=$?
assert_equal "$launcher_status" "23" "oe propagates the launcher exit status"

missing_launcher_status=0
missing_launcher_output=$(PROTOCODE_BIN="$sandbox/missing-protocode" oe 2>&1) || missing_launcher_status=$?
assert_equal "$missing_launcher_status" "1" "oe fails when the launcher is missing"
assert_contains "$missing_launcher_output" "install.zsh" "oe names the launcher setup command"

# The static wrapper applies isolation and updater policy for every invocation,
# including callers that bypass oe.
wrapper_install="$sandbox/protocode install"
wrapper_capture="$sandbox/wrapper-output"
mkdir -p "$wrapper_install/builds/test-build"
{
  print '#!/bin/zsh -f'
  print 'print -r -- "autoupdate=$OPENCODE_DISABLE_AUTOUPDATE"'
  print 'print -r -- "data=$XDG_DATA_HOME"'
  print 'print -r -- "state=$XDG_STATE_HOME"'
  print 'print -r -- "cache=$XDG_CACHE_HOME"'
  print 'print -r -- "config=${XDG_CONFIG_HOME:-}"'
  print 'print -rl -- "$@"'
} > "$wrapper_install/builds/test-build/protocode"
chmod 755 "$wrapper_install/builds/test-build/protocode"
ln -s "builds/test-build" "$wrapper_install/current"

wrapper_output=$(HOME="$sandbox" PROTOCODE_INSTALL_ROOT="$wrapper_install" \
  XDG_CONFIG_HOME="$sandbox/shared-config" "$root/bin/protocode" "one two" three)
assert_contains "$wrapper_output" "autoupdate=1" "wrapper disables Protocode auto-update"
assert_contains "$wrapper_output" "data=$wrapper_install/xdg-data" "wrapper isolates data"
assert_contains "$wrapper_output" "state=$wrapper_install/xdg-state" "wrapper isolates state"
assert_contains "$wrapper_output" "cache=$wrapper_install/xdg-cache" "wrapper isolates cache"
assert_contains "$wrapper_output" "config=$sandbox/shared-config" "wrapper preserves shared configuration"
assert_contains "$wrapper_output" "one two" "wrapper preserves spaced arguments"

wrapper_output=$(HOME="$sandbox" PROTOCODE_INSTALL_ROOT="$wrapper_install" \
  PROTOCODE_DATA_HOME="$sandbox/custom-data" PROTOCODE_STATE_HOME="$sandbox/custom-state" \
  PROTOCODE_CACHE_HOME="$sandbox/custom-cache" "$root/bin/protocode")
assert_contains "$wrapper_output" "data=$sandbox/custom-data" "wrapper accepts a data override"
assert_contains "$wrapper_output" "state=$sandbox/custom-state" "wrapper accepts a state override"
assert_contains "$wrapper_output" "cache=$sandbox/custom-cache" "wrapper accepts a cache override"

missing_build_status=0
missing_build_output=$(HOME="$sandbox" PROTOCODE_INSTALL_ROOT="$sandbox/missing-install" \
  "$root/bin/protocode" 2>&1) || missing_build_status=$?
assert_equal "$missing_build_status" "1" "wrapper fails when the active build is missing"
assert_contains "$missing_build_output" "protocode-build.zsh" "wrapper names the build command"

# Promotion is a recoverable state machine. Every injected failure restores
# the old pin/current pair and removes a target created by the failed run.
promote_install="$sandbox/promote-install"
promote_pin="$sandbox/promote.pin"
promote_artifact="$wrapper_install/builds/test-build/protocode"
promote_upstream=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
promote_old=1111111111111111111111111111111111111111

PROTOCODE_ARTIFACT="$promote_artifact" PROTOCODE_COMMIT="$promote_old" \
  PROTOCODE_UPSTREAM_TAG=v1.18.18 PROTOCODE_UPSTREAM_COMMIT="$promote_upstream" \
  PROTOCODE_RELEASE_TAG=protocode-1.18.18-r1 PROTOCODE_INSTALL_ROOT="$promote_install" \
  PROTOCODE_PIN_FILE="$promote_pin" "$root/scripts/protocode-promote.zsh" >/dev/null
assert_equal "$(readlink "$promote_install/current")" "builds/$promote_old" "promotion activates a verified build"
assert_contains "$(cat "$promote_pin")" "UPSTREAM_COMMIT=$promote_upstream" "promotion records upstream provenance"

assert_failed_promotion_restores() {
  local point="$1" candidate="$2"
  local promote_status=0
  PROTOCODE_ARTIFACT="$promote_artifact" PROTOCODE_COMMIT="$candidate" \
    PROTOCODE_UPSTREAM_TAG=v1.18.18 PROTOCODE_UPSTREAM_COMMIT="$promote_upstream" \
    PROTOCODE_RELEASE_TAG=protocode-1.18.18-r2 PROTOCODE_INSTALL_ROOT="$promote_install" \
    PROTOCODE_PIN_FILE="$promote_pin" PROTOCODE_PROMOTE_FAIL_AT="$point" \
    "$root/scripts/protocode-promote.zsh" >/dev/null 2>&1 || promote_status=$?
  if (( promote_status == 0 )); then
    print -u2 -- "FAIL promotion fails after $point"
    exit 1
  fi
  (( assertions += 1 ))
  assert_equal "$(readlink "$promote_install/current")" "builds/$promote_old" "failure after $point restores current"
  assert_contains "$(cat "$promote_pin")" "COMMIT=$promote_old" "failure after $point restores pin"
  assert_absent "$promote_install/builds/$candidate" "failure after $point removes candidate"
}

assert_failed_promotion_restores target 2222222222222222222222222222222222222222
assert_failed_promotion_restores pin 3333333333333333333333333333333333333333
assert_failed_promotion_restores current 4444444444444444444444444444444444444444

first_install="$sandbox/promote-first-install"
first_pin="$sandbox/promote-first.pin"
first_commit=5555555555555555555555555555555555555555
first_status=0
PROTOCODE_ARTIFACT="$promote_artifact" PROTOCODE_COMMIT="$first_commit" \
  PROTOCODE_UPSTREAM_TAG=v1.18.18 PROTOCODE_UPSTREAM_COMMIT="$promote_upstream" \
  PROTOCODE_RELEASE_TAG=protocode-1.18.18-r1 PROTOCODE_INSTALL_ROOT="$first_install" \
  PROTOCODE_PIN_FILE="$first_pin" PROTOCODE_PROMOTE_FAIL_AT=current \
  "$root/scripts/protocode-promote.zsh" >/dev/null 2>&1 || first_status=$?
if (( first_status == 0 )); then
  print -u2 -- "FAIL interrupted first promotion exits nonzero"
  exit 1
fi
(( assertions += 1 ))
assert_absent "$first_install/current" "interrupted first promotion removes current"
assert_absent "$first_pin" "interrupted first promotion removes pin"
assert_absent "$first_install/builds/$first_commit" "interrupted first promotion removes candidate"

# Retention keeps the newest three builds, including the active target.
promote_latest=''
integer promote_revision=2
for promote_latest in \
  6666666666666666666666666666666666666666 \
  7777777777777777777777777777777777777777 \
  8888888888888888888888888888888888888888; do
  PROTOCODE_ARTIFACT="$promote_artifact" PROTOCODE_COMMIT="$promote_latest" \
    PROTOCODE_UPSTREAM_TAG=v1.18.18 PROTOCODE_UPSTREAM_COMMIT="$promote_upstream" \
    PROTOCODE_RELEASE_TAG="protocode-1.18.18-r$promote_revision" PROTOCODE_INSTALL_ROOT="$promote_install" \
    PROTOCODE_PIN_FILE="$promote_pin" "$root/scripts/protocode-promote.zsh" >/dev/null
  (( promote_revision += 1 ))
done
assert_absent "$promote_install/builds/$promote_old" "retention removes the oldest build"
assert_equal "$(readlink "$promote_install/current")" "builds/$promote_latest" "retention preserves the active link"
assert_executable "$promote_install/current/protocode" "retention preserves the active executable"
promote_builds=("$promote_install/builds"/*(/N))
assert_equal "${#promote_builds}" "3" "retention keeps exactly three builds"

# The build process transfers its PID to promotion with exec. TERM sent to that
# orchestrator PID rolls back a promotion paused after replacing current.
signal_candidate=9999999999999999999999999999999999999999
signal_marker="$sandbox/promotion-paused"
signal_lock="$promote_install/.build-lock"
mkdir "$signal_lock"
PROTOCODE_ARTIFACT="$promote_artifact" PROTOCODE_COMMIT="$signal_candidate" \
  PROTOCODE_UPSTREAM_TAG=v1.18.18 PROTOCODE_UPSTREAM_COMMIT="$promote_upstream" \
  PROTOCODE_RELEASE_TAG=protocode-1.18.18-r5 PROTOCODE_INSTALL_ROOT="$promote_install" \
  PROTOCODE_PIN_FILE="$promote_pin" PROTOCODE_BUILD_LOCK_DIR="$signal_lock" \
  PROTOCODE_PROMOTE_PAUSE_AT=current PROTOCODE_PROMOTE_PAUSE_FILE="$signal_marker" \
  PROMOTE_SCRIPT="$root/scripts/protocode-promote.zsh" \
  /bin/zsh -c 'exec "$PROMOTE_SCRIPT"' >/dev/null 2>&1 &
signal_pid=$!
integer signal_attempt=0
while [[ ! -f "$signal_marker" ]] && (( signal_attempt < 100 )); do
  /bin/sleep 0.02
  (( signal_attempt += 1 ))
done
if [[ ! -f "$signal_marker" ]]; then
  kill -TERM "$signal_pid" 2>/dev/null || true
  wait "$signal_pid" 2>/dev/null || true
  print -u2 -- "FAIL promotion reached the signal pause"
  exit 1
fi
(( assertions += 1 ))
kill -TERM "$signal_pid"
signal_status=0
wait "$signal_pid" || signal_status=$?
assert_equal "$signal_status" "143" "TERM exits the promotion owner with signal status"
assert_equal "$(readlink "$promote_install/current")" "builds/$promote_latest" "TERM restores the previous current link"
assert_contains "$(cat "$promote_pin")" "COMMIT=$promote_latest" "TERM restores the previous pin"
assert_absent "$promote_install/builds/$signal_candidate" "TERM removes the interrupted candidate"
assert_absent "$signal_lock" "TERM releases the transferred build lock"

early_lock="$sandbox/early-promotion/.build-lock"
mkdir -p "$early_lock"
early_status=0
PROTOCODE_ARTIFACT="$sandbox/missing-artifact" PROTOCODE_COMMIT="$signal_candidate" \
  PROTOCODE_UPSTREAM_TAG=v1.18.18 PROTOCODE_UPSTREAM_COMMIT="$promote_upstream" \
  PROTOCODE_RELEASE_TAG=protocode-1.18.18-r5 PROTOCODE_INSTALL_ROOT="$sandbox/early-promotion" \
  PROTOCODE_PIN_FILE="$sandbox/early-promotion.pin" PROTOCODE_BUILD_LOCK_DIR="$early_lock" \
  "$root/scripts/protocode-promote.zsh" >/dev/null 2>&1 || early_status=$?
if (( early_status == 0 )); then
  print -u2 -- "FAIL early promotion validation exits nonzero"
  exit 1
fi
(( assertions += 1 ))
assert_absent "$early_lock" "early promotion validation releases the transferred build lock"

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
assert_same_file "$sandbox/.local/bin/protocode" "$root/bin/protocode" "installer copies the Protocode wrapper"

print '# locally stale managed wrapper' >> "$sandbox/.local/bin/protocode"
install_output=$(in_sandbox "$root/install.zsh")
assert_same_file "$sandbox/.local/bin/protocode" "$root/bin/protocode" "installer atomically upgrades its managed wrapper"
doctor_output=$(in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "installed links and shell integration" "doctor confirms links after install"

# doctor: a clean stable source, matching release tags, pin, wrapper, and active
# build form one verified Protocode installation.
doctor_source="$sandbox/protocode-source"
doctor_install="$sandbox/protocode-install"
doctor_pin="$sandbox/protocode.pin"
git init -q -b stable "$doctor_source"
git -C "$doctor_source" config user.name "Protocol Test"
git -C "$doctor_source" config user.email "protocol@example.com"
print fixture > "$doctor_source/fixture"
git -C "$doctor_source" add fixture
git -C "$doctor_source" commit -qm "upstream fixture"
doctor_upstream_commit=$(git -C "$doctor_source" rev-parse HEAD)
git -C "$doctor_source" tag -a v1.18.18 -m "upstream fixture"
doctor_upstream_tag_object=$(git -C "$doctor_source" rev-parse v1.18.18)
git -C "$doctor_source" update-ref refs/protocode/upstream-tags/v1.18.18 "$doctor_upstream_commit"
print divergence >> "$doctor_source/fixture"
git -C "$doctor_source" add fixture
git -C "$doctor_source" commit -qm "distribution fixture"
doctor_commit=$(git -C "$doctor_source" rev-parse HEAD)
git -C "$doctor_source" tag protocode-1.18.18-r1
mkdir -p "$doctor_install/builds/$doctor_commit"
cp "$wrapper_install/builds/test-build/protocode" "$doctor_install/builds/$doctor_commit/protocode"
ln -s "builds/$doctor_commit" "$doctor_install/current"
doctor_artifact_sha=$(/usr/bin/shasum -a 256 "$doctor_install/current/protocode")
doctor_artifact_sha="${doctor_artifact_sha%% *}"
{
  print 'UPSTREAM_TAG=v1.18.18'
  print -r -- "UPSTREAM_COMMIT=$doctor_upstream_commit"
  print 'PROTOCODE_TAG=protocode-1.18.18-r1'
  print -r -- "COMMIT=$doctor_commit"
  print -r -- "ARTIFACT_SHA256=$doctor_artifact_sha"
  print 'BUILT=2026-08-16T00:00:00Z'
} > "$doctor_pin"
git -C "$doctor_source" remote add upstream https://github.com/anomalyco/opencode.git

doctor_output=$(PROTOCODE_SOURCE_ROOT="$doctor_source" PROTOCODE_INSTALL_ROOT="$doctor_install" \
  PROTOCODE_PIN_FILE="$doctor_pin" PROTOCODE_BIN="$root/bin/protocode" \
  in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "source matches pinned commit" "doctor verifies the Protocode source pin"
assert_contains "$doctor_output" "upstream tag matches fetched provenance" "doctor accepts lightweight fetched provenance"
assert_contains "$doctor_output" "artifact digest match pin" "doctor verifies the active Protocode artifact"

git -C "$doctor_source" update-ref refs/protocode/upstream-tags/v1.18.18 "$doctor_upstream_tag_object"
doctor_output=$(PROTOCODE_SOURCE_ROOT="$doctor_source" PROTOCODE_INSTALL_ROOT="$doctor_install" \
  PROTOCODE_PIN_FILE="$doctor_pin" PROTOCODE_BIN="$root/bin/protocode" \
  in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "upstream tag matches fetched provenance" "doctor accepts annotated fetched provenance"

git -C "$doctor_source" update-ref refs/protocode/upstream-tags/v1.18.18 "$doctor_commit"
doctor_output=$(PROTOCODE_SOURCE_ROOT="$doctor_source" PROTOCODE_INSTALL_ROOT="$doctor_install" \
  PROTOCODE_PIN_FILE="$doctor_pin" PROTOCODE_BIN="$root/bin/protocode" \
  in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "provenance does not match pin" "doctor rejects mismatched fetched provenance"
git -C "$doctor_source" update-ref -d refs/protocode/upstream-tags/v1.18.18
doctor_output=$(PROTOCODE_SOURCE_ROOT="$doctor_source" PROTOCODE_INSTALL_ROOT="$doctor_install" \
  PROTOCODE_PIN_FILE="$doctor_pin" PROTOCODE_BIN="$root/bin/protocode" \
  in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "provenance does not match pin" "doctor rejects missing fetched provenance"
git -C "$doctor_source" update-ref refs/protocode/upstream-tags/v1.18.18 "$doctor_upstream_tag_object"

rm "$doctor_install/current"
ln -s "builds/missing" "$doctor_install/current"
doctor_output=$(PROTOCODE_SOURCE_ROOT="$sandbox/missing-source" PROTOCODE_INSTALL_ROOT="$doctor_install" \
  PROTOCODE_PIN_FILE="$doctor_pin" PROTOCODE_BIN="$root/bin/protocode" \
  in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "source clone missing" "doctor treats a dangling current link as partial configuration"
rm "$doctor_install/current"
ln -s "builds/$doctor_commit" "$doctor_install/current"

print dirty > "$doctor_source/untracked"
doctor_output=$(PROTOCODE_SOURCE_ROOT="$doctor_source" PROTOCODE_INSTALL_ROOT="$doctor_install" \
  PROTOCODE_PIN_FILE="$doctor_pin" PROTOCODE_BIN="$root/bin/protocode" \
  in_sandbox "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$doctor_output" "source worktree has changes" "doctor reports a dirty Protocode source"

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

# A separate machine-specific config repository owns every live configuration
# artifact, including the static wrapper; Protocol supplies portable tooling.
overlay_home="$sandbox/overlay home"
overlay_root="$sandbox/local config"
mkdir -p "$overlay_home" "$overlay_root/nvim" "$overlay_root/ghostty" "$overlay_root/shell"
print -r -- "source ${(q)root}/shell/protocol.zsh" > "$overlay_root/shell/zshrc"
cp "$root/bin/protocode" "$overlay_root/shell/protocode"
print '# external-config-owner' >> "$overlay_root/shell/protocode"
chmod 755 "$overlay_root/shell/protocode"

overlay_install_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" \
  XDG_CONFIG_HOME="$overlay_home/.config" PROTOCOL_CONFIG_ROOT="$overlay_root" \
  "$root/install.zsh")
assert_contains "$overlay_install_output" "protocol installed" "overlay installer succeeds"
assert_link "$overlay_home/.zshrc" "$overlay_root/shell/zshrc" "overlay owns zshrc"
assert_link "$overlay_home/.config/nvim" "$overlay_root/nvim" "overlay owns Neovim"
assert_link "$overlay_home/.config/ghostty" "$overlay_root/ghostty" "overlay owns Ghostty"
assert_same_file "$overlay_home/.local/bin/protocode" "$overlay_root/shell/protocode" "external config root installs its live wrapper"

overlay_check_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" \
  XDG_CONFIG_HOME="$overlay_home/.config" PROTOCOL_CONFIG_ROOT="$overlay_root" \
  "$root/install.zsh" --check)
assert_contains "$overlay_check_output" "installation is valid" "overlay check succeeds"

overlay_doctor_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" \
  XDG_CONFIG_HOME="$overlay_home/.config" PROTOCOL_CONFIG_ROOT="$overlay_root" \
  "$root/scripts/doctor.zsh" 2>&1) || true
assert_contains "$overlay_doctor_output" "installed links and shell integration" "doctor accepts overlay links"

missing_skills_status=0
missing_skills_output=$(HOME="$overlay_home" ZDOTDIR="$overlay_home" XDG_CONFIG_HOME="$overlay_home/.config" \
  PROTOCOL_CONFIG_ROOT="$overlay_root" PROTOCOL_SKILLS_ROOT="$sandbox/missing-skills" \
  "$root/install.zsh" --check 2>&1) || missing_skills_status=$?
assert_equal "$missing_skills_status" "1" "installer rejects a missing skills override"
assert_contains "$missing_skills_output" "skills source missing" "installer reports the missing skills source"

print "shell tests passed ($assertions assertions)"
