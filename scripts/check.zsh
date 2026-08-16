#!/bin/zsh

set -eu
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

root="${0:A:h:h}"
required=(
  README.md
  LICENSE
  SETUP.md
  install.zsh
  shell/protocol.zsh
  shell/repo-colors.conf
  git-hooks/dispatch.sh
  git-hooks/README.md
  scripts/doctor.zsh
  tests/shell_test.zsh
  tests/nvim_test.zsh
  ghostty/bin/ghostty-theme
  nvim/init.lua
  agent/AGENTS.md
  knowledge-vault/init.zsh
  pr-review/README.md
)

for required_path in $required; do
  if [[ ! -e "$root/$required_path" ]]; then
    print -u2 "missing required path: $required_path"
    exit 1
  fi
done

for script in "$root/install.zsh" "$root/scripts/check.zsh" "$root/scripts/doctor.zsh" "$root/tests/shell_test.zsh" "$root/tests/nvim_test.zsh" "$root/knowledge-vault/init.zsh" "$root/ghostty/bin/ghostty-theme"; do
  /bin/zsh -n "$script"
  if [[ ! -x "$script" ]]; then
    print -u2 "script is not executable: ${script#$root/}"
    exit 1
  fi
done

/bin/zsh -n "$root/shell/protocol.zsh"

# The hook dispatcher is bash (git invokes hooks via their shebang).
bash -n "$root/git-hooks/dispatch.sh"
if [[ ! -x "$root/git-hooks/dispatch.sh" ]]; then
  print -u2 "script is not executable: git-hooks/dispatch.sh"
  exit 1
fi

# The shell module must also *source* cleanly, with status 0, in a bare shell
# running under errexit -- syntax checking alone missed a trailing &&-list
# that returned nonzero whenever an optional tool was absent.
PROTOCOL_CHECK_MODULE="$root/shell/protocol.zsh" \
  /bin/zsh -fec 'source "$PROTOCOL_CHECK_MODULE"'
python3 -m py_compile "$root/agent/hooks/semantic-title.py"

# In a linked git worktree, .git is a pointer file whose content is an
# absolute path, so it must be excluded by name as well as by directory.
if grep -RIE '/Users/|Co-Authored-By:|T-[A-Z][0-9-]+' \
  --exclude-dir=.git --exclude=.git --exclude='check.zsh' "$root" >/dev/null; then
  print -u2 "privacy check failed: local path, task ID, or attribution trailer found"
  exit 1
fi

if find "$root" -type l ! -exec test -e {} \; -print -quit | grep -q .; then
  print -u2 "broken symbolic link found"
  exit 1
fi

print "protocol checks passed"
