# Portable interactive zsh configuration.

typeset -g PROTOCOL_ROOT="${${(%):-%N}:A:h:h}"
export CODE_WORKSPACE="${CODE_WORKSPACE:-$HOME/Code}"
export PROTOCOL_FRICTION_LOG="${PROTOCOL_FRICTION_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/protocol/friction-log.md}"

typeset -gA PROTOCOL_REPO_COLORS
typeset -ga PROTOCOL_REPO_PALETTE=(131 71 67 133 173 179 98 109 144 174 103 72 137 110 180 139)
typeset -gA _PROTOCOL_REPO_COLOR_CACHE

protocol_repo_prompt() {
  if [[ "$PWD" == "$CODE_WORKSPACE"/* ]]; then
    local repo="${PWD#$CODE_WORKSPACE/}"
    repo="${repo%%/*}"
    local color
    if [[ -n "${PROTOCOL_REPO_COLORS[$repo]+x}" ]]; then
      color="${PROTOCOL_REPO_COLORS[$repo]}"
    elif [[ -n "${_PROTOCOL_REPO_COLOR_CACHE[$repo]+x}" ]]; then
      color="${_PROTOCOL_REPO_COLOR_CACHE[$repo]}"
    else
      local hash
      hash=$(print -rn -- "$repo" | cksum | awk '{print $1}')
      color="${PROTOCOL_REPO_PALETTE[$((hash % ${#PROTOCOL_REPO_PALETTE[@]} + 1))]}"
      _PROTOCOL_REPO_COLOR_CACHE[$repo]="$color"
    fi
    if [[ "$PWD" == "$CODE_WORKSPACE/$repo" ]]; then
      PS1="%F{$color}$repo%f %% "
    else
      PS1="%F{$color}$repo%f:%1~ %% "
    fi
  else
    PS1="%1~ %% "
  fi
}

precmd_functions=("${(@)precmd_functions:#protocol_repo_prompt}")
precmd_functions+=(protocol_repo_prompt)

protocol_random_color() {
  local -a colors=(red blue green yellow purple orange pink cyan)
  print -r -- "${colors[$((RANDOM % ${#colors[@]} + 1))]}"
}

protocol_start_claude() {
  local session_id="${$(uuidgen):l}"
  local color="$(protocol_random_color)"
  command claude -p --session-id "$session_id" "/color $color" >/dev/null || return
  command claude --resume "$session_id" "$@"
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
  command claude "${args[@]}"
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
alias oe='opencode --auto'
alias sz='source ~/.zshrc'
alias theme="$PROTOCOL_ROOT/ghostty/bin/ghostty-theme"
alias doctor="$PROTOCOL_ROOT/scripts/doctor.zsh"

# if-guards, not &&-lists: a missing optional tool must not become a nonzero
# exit status for this file, or sourcing it under errexit aborts the shell.
if [[ -f "$HOME/.fzf.zsh" ]]; then
  source "$HOME/.fzf.zsh"
fi
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
