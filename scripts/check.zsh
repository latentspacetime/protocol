#!/bin/zsh

set -eu
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

root="${0:A:h:h}"
required=(
  README.md
  LICENSE
  install.zsh
  shell/protocol.zsh
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

for script in "$root/install.zsh" "$root/scripts/check.zsh" "$root/knowledge-vault/init.zsh" "$root/ghostty/bin/ghostty-theme"; do
  /bin/zsh -n "$script"
  if [[ ! -x "$script" ]]; then
    print -u2 "script is not executable: ${script#$root/}"
    exit 1
  fi
done

/bin/zsh -n "$root/shell/protocol.zsh"
python3 -m py_compile "$root/agent/hooks/semantic-title.py"

if grep -RIE '/Users/|Co-Authored-By:|T-[A-Z][0-9-]+' \
  --exclude-dir=.git --exclude='check.zsh' "$root" >/dev/null; then
  print -u2 "privacy check failed: local path, task ID, or attribution trailer found"
  exit 1
fi

if find "$root" -type l ! -exec test -e {} \; -print -quit | grep -q .; then
  print -u2 "broken symbolic link found"
  exit 1
fi

print "protocol checks passed"
