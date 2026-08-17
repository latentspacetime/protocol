# Portable interactive zsh configuration.

typeset -gx PROTOCOL_ROOT="${${(%):-%N}:A:h:h}"
export CODE_WORKSPACE="${CODE_WORKSPACE:-$HOME/Code}"
export PROTOCOL_FRICTION_LOG="${PROTOCOL_FRICTION_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/protocol/friction-log.md}"
export PROTOCOL_REPO_COLOR_CONFIG="${PROTOCOL_REPO_COLOR_CONFIG:-$PROTOCOL_ROOT/shell/repo-colors.conf}"

typeset -gA PROTOCOL_REPO_COLORS
typeset -ga PROTOCOL_REPO_PALETTE=(131 71 67 133 173 179 98 109 144 174 103 72 137 110 180 139)
typeset -gA _PROTOCOL_REPO_COLOR_CACHE=()

protocol_load_repo_colors() {
  typeset -A loaded_colors=()
  if [[ ! -r "$PROTOCOL_REPO_COLOR_CONFIG" ]]; then
    PROTOCOL_REPO_COLORS=()
    return 0
  fi
  local repo color
  while IFS='=' read -r repo color || [[ -n "$repo$color" ]]; do
    [[ -z "$repo" || "$repo" == \#* ]] && continue
    if [[ -z "$color" || "$color" != <-> || $color -lt 0 || $color -gt 255 ]]; then
      print -u2 -- "invalid repository color in $PROTOCOL_REPO_COLOR_CONFIG: $repo=$color"
      return 1
    fi
    loaded_colors[$repo]="$color"
  done < "$PROTOCOL_REPO_COLOR_CONFIG"
  PROTOCOL_REPO_COLORS=("${(@kv)loaded_colors}")
}

if [[ "$ZSH_EVAL_CONTEXT" == *file* ]]; then
  protocol_load_repo_colors || :
fi

# Canonical repository-color resolver shared by the prompt and Neovim picker.
# Sets REPLY to one Ghostty-compatible 256-color palette index.
protocol_repo_color() {
  local repo="$1"
  if [[ -n "${PROTOCOL_REPO_COLORS[$repo]+x}" ]]; then
    REPLY="${PROTOCOL_REPO_COLORS[$repo]}"
  elif [[ -n "${_PROTOCOL_REPO_COLOR_CACHE[$repo]+x}" ]]; then
    REPLY="${_PROTOCOL_REPO_COLOR_CACHE[$repo]}"
  else
    local hash
    hash=$(echo -n "$repo" | cksum | awk '{print $1}')
    REPLY="${PROTOCOL_REPO_PALETTE[$((hash % ${#PROTOCOL_REPO_PALETTE[@]} + 1))]}"
    _PROTOCOL_REPO_COLOR_CACHE[$repo]="$REPLY"
  fi
}

if [[ "$ZSH_EVAL_CONTEXT" != *file* && "${1:-}" == "--repo-colors" ]]; then
  protocol_load_repo_colors || exit 1
  shift
  for _protocol_repo_name in "$@"; do
    protocol_repo_color "$_protocol_repo_name"
    print -r -- "$REPLY"
  done
  unset _protocol_repo_name
  return 0 2>/dev/null || exit 0
fi

protocol_repo_prompt() {
  protocol_load_repo_colors || return
  if [[ "$PWD" == "$CODE_WORKSPACE"/* ]]; then
    local repo="${PWD#$CODE_WORKSPACE/}"
    repo="${repo%%/*}"
    protocol_repo_color "$repo"
    local color="$REPLY"
    if [[ "$PWD" == "$CODE_WORKSPACE/$repo" ]]; then
      PS1="%F{$color}$repo%f %% "
    else
      PS1="%F{$color}$repo%f:%1~ %% "
    fi
  else
    PS1="${PROTOCOL_PROMPT_FALLBACK:-%1~ %% }"
  fi
}

precmd_functions=("${(@)precmd_functions:#protocol_repo_prompt}")
precmd_functions+=(protocol_repo_prompt)

protocol_random_color() {
  local -a colors=(red blue green yellow purple orange pink cyan)
  print -r -- "${colors[$((RANDOM % ${#colors[@]} + 1))]}"
}

# Claude Code writes transcripts under the logical cwd and looks them up
# with realpath. Launching from a symlink (workspace doc route, ~/.config/nvim)
# therefore stores a session that later --resume cannot see.
protocol_claude_project_key() {
  print -r -- "${${${1:-$PWD}:A}//[^a-zA-Z0-9]/-}"
}

protocol_claude_session_path() {
  local session_id="$1"
  local dir="${2:-$PWD}"
  local root="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  print -r -- "$root/projects/$(protocol_claude_project_key "$dir")/${session_id}.jsonl"
}

protocol_claude_session_is_stub() {
  local file="$1" line contents
  [[ -f "$file" ]] || return 1
  contents="$(<"$file")"
  [[ "$contents" == *'"type":"agent-color"'* || "$contents" == *'"type": "agent-color"'* ]] || return 1
  [[ "$contents" == *'"customTitle":"'* || "$contents" == *'"aiTitle":"'* ]] && return 1
  while IFS= read -r line; do
    if [[ "$line" != *'"type":"user"'* && "$line" != *'"type": "user"'* ]]; then
      continue
    fi
    if [[ "$line" == *'<command-name>'* || "$line" == *'<local-command-stdout>'* ]]; then
      continue
    fi
    if [[ "$line" == *'"isMeta":true'* || "$line" == *'"isMeta": true'* ]]; then
      continue
    fi
    return 1
  done < "$file"
  return 0
}

protocol_reap_claude_color_stub() {
  local file="$1"
  protocol_claude_session_is_stub "$file" || return 0
  /bin/rm -f "$file"
}

protocol_reap_claude_color_stubs() {
  local projects="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
  local file
  [[ -d "$projects" ]] || return 0
  for file in "$projects"/*/*.jsonl(N); do
    protocol_reap_claude_color_stub "$file"
  done
}

protocol_claude_in_canonical_dir() {
  local launch_dir="${PWD:A}"
  (
    cd "$launch_dir" || exit
    "$@"
  )
}

protocol_start_claude() {
  local session_id="${$(uuidgen):l}"
  local color="$(protocol_random_color)"
  local launch_dir="${PWD:A}"
  (
    cd "$launch_dir" || exit
    command claude -p --session-id "$session_id" "/color $color" >/dev/null || exit
    command claude --resume "$session_id" "$@"
    local rc=$?
    protocol_reap_claude_color_stub "$(protocol_claude_session_path "$session_id" "$launch_dir")"
    exit $rc
  )
}

claude() {
  local -a args=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--dsp" ]]; then
      args+=(--dangerously-skip-permissions)
    else
      args+=("$arg")
    fi
  done
  if (( ${#args[@]} == 0 )); then
    protocol_start_claude
    return
  fi
  protocol_claude_in_canonical_dir command claude "${args[@]}"
}

codex() {
  local -a args=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--dsp" ]]; then
      args+=(--dangerously-bypass-approvals-and-sandbox)
    else
      args+=("$arg")
    fi
  done
  command codex "${args[@]}"
}

ci() {
  if (( $# == 0 )); then
    protocol_start_claude --model "${PROTOCOL_CLAUDE_MODEL:-opus}" --dangerously-skip-permissions --effort xhigh
    return
  fi
  claude --model "${PROTOCOL_CLAUDE_MODEL:-opus}" --dsp --effort xhigh "$@"
}

wt() {
  if [[ -z "${1:-}" ]]; then
    git worktree list 2>/dev/null || print "not in a git repository"
    return
  fi

  local target porcelain
  porcelain=$(git worktree list --porcelain 2>/dev/null)
  [[ -z "$porcelain" ]] && { print "not in a git repository"; return 1; }

  target=$(print -r -- "$porcelain" | awk -v name="$1" '
    /^worktree / { path=$2 }
    /^branch / { sub(/.*\//, "", $2); if ($2 == name) { print path; exit } }')
  [[ -z "$target" ]] && target=$(print -r -- "$porcelain" | awk -v name="$1" '
    /^worktree / { path=$2 }
    /^branch / { sub(/.*\//, "", $2); if (index($2, name) == 1) { print path; exit } }')
  [[ -z "$target" ]] && target=$(print -r -- "$porcelain" | awk -v name="$1" '
    /^worktree / { path=$2 }
    /^branch / { sub(/.*\//, "", $2); if (index($2, name) > 0) { print path; exit } }')
  # Last resort: match the worktree directory path, for worktrees whose
  # directory name carries the identity while the branch name does not.
  [[ -z "$target" ]] && target=$(git worktree list 2>/dev/null | awk -v name="$1" '
    $0 ~ name { print $1; exit }')

  if [[ -n "$target" ]]; then
    cd "$target"
  else
    print "worktree '$1' not found"
    git worktree list 2>/dev/null
    return 1
  fi
}

gs() {
  if [[ -z "${1:-}" ]]; then
    git branch 2>/dev/null
    return
  fi

  local match branches
  branches=$(git branch --format='%(refname:short)' 2>/dev/null)
  [[ -z "$branches" ]] && { print "not in a git repository"; return 1; }
  match=$(print -r -- "$branches" | awk -v name="$1" 'BEGIN { IGNORECASE=1 } index($0, name) == 1 { print; exit }')
  [[ -z "$match" ]] && match=$(print -r -- "$branches" | awk -v name="$1" 'BEGIN { IGNORECASE=1 } index($0, name) > 0 { print; exit }')
  if [[ -n "$match" ]]; then
    git switch "$match"
  else
    print "no branch matching '$1'"
    print -r -- "$branches"
    return 1
  fi
}

cbfix() {
  pbpaste | perl -0777 -pe 's/(\S) *\n {2,}/$1 /g' | pbcopy
  print "Clipboard unwrapped."
}

# ugh [message] -- capture a workflow annoyance the moment it happens, so
# tooling improvements start from a frequency-ranked record instead of recall.
# With a message: append one timestamped entry with directory and git branch.
# Without: show the log location, entry count, and most recent entries.
ugh() {
  local log="$PROTOCOL_FRICTION_LOG"

  if (( $# == 0 )); then
    if [[ ! -f "$log" ]]; then
      print "friction log is empty ($log)"
      return
    fi
    print "$(grep -c '^- ' "$log") entries in $log, most recent:"
    grep '^- ' "$log" | tail -5
    return
  fi

  if [[ ! -f "$log" ]]; then
    mkdir -p "${log:h}"
    {
      print -r -- "# Friction Log"
      print
      print -r -- "Workflow annoyances captured with the ugh command, one line each,"
      print -r -- "recorded the moment they happened. Review before tooling work."
      print
    } > "$log"
  fi

  local where="${PWD/#$HOME/~}"
  local branch
  # Outside a repository git exits nonzero; that must not abort ugh when the
  # calling shell runs under errexit.
  branch=$(git branch --show-current 2>/dev/null) || true
  [[ -n "$branch" ]] && where="$where ($branch)"
  print -r -- "- $(date '+%Y-%m-%d %H:%M') $where: $*" >> "$log"
  print "logged ($(grep -c '^- ' "$log") total)"
}

alias gpo='git pull origin'
unalias oe 2>/dev/null || true
oe() {
  local launcher="${PROTOCODE_BIN:-$HOME/.local/bin/protocode}"
  if [[ ! -x "$launcher" ]]; then
    print -u2 -- "protocode launcher missing: $launcher"
    print -u2 -- "Run: ${PROTOCOL_TOOLKIT_ROOT:-${CODE_WORKSPACE:-$HOME/Code}/protocol}/install.zsh"
    return 1
  fi
  "$launcher" --auto "$@"
}
alias sz='source ~/.zshrc'
alias theme="$PROTOCOL_ROOT/ghostty/bin/ghostty-theme"
# The doctor script lives in the protocol toolkit repository. When this module
# is vendored into a separate live-configuration root, PROTOCOL_TOOLKIT_ROOT
# names the toolkit checkout; by default the module's own repository has it.
alias doctor="${PROTOCOL_TOOLKIT_ROOT:-$PROTOCOL_ROOT}/scripts/doctor.zsh"

# if-guards, not &&-lists: a missing optional tool must not become a nonzero
# exit status for this file, or sourcing it under errexit aborts the shell.
if [[ -f "$HOME/.fzf.zsh" ]]; then
  source "$HOME/.fzf.zsh"
fi
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
