#!/usr/bin/env bash
# Global git hook dispatcher.
# Install by pointing core.hooksPath at a directory of hook-name symlinks
# that all resolve to this script (see README.md in this directory). The
# script determines which hook was invoked from $0, runs any global
# enforcement for that hook type, then chains to the repository's own
# .git/hooks/<name> if one exists, so per-repository hooks keep working.

HOOK_NAME="$(basename "$0")"

# ── Global enforcement ──────────────────────────────────────────────
case "$HOOK_NAME" in
  commit-msg)
    msgfile="$1"
    if [ -f "$msgfile" ]; then
      # Agent attribution patterns (case-insensitive).
      # Matches co-author trailers referencing known AI agents/companies
      # and "Generated with" / "Built with" footers.
      attribution_re='[Cc]o-[Aa]uthored-[Bb]y:.*\b([Cc]laude|[Aa]nthropic|GPT|[Oo]pen[Aa][Ii]|[Cc]opilot|[Cc]odex|[Cc]ursor|[Dd]evin|[Aa]ider|[Gg]emini|[Mm]istral)\b'
      noreply_re='[Cc]o-[Aa]uthored-[Bb]y:.*noreply@anthropic\.com'
      generated_re='Generated with \[?[Cc]laude'
      built_re='Built with \[?[Cc]laude'
      robot_re='^🤖'

      # Strip matching lines from the commit message.
      tmp="$(mktemp)"
      grep -vE "$attribution_re" "$msgfile" \
        | grep -vE "$noreply_re" \
        | grep -vE "$generated_re" \
        | grep -vE "$built_re" \
        | grep -v "$robot_re" \
        > "$tmp"

      # Remove trailing blank lines left behind by stripped trailers.
      sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" > "$msgfile"
      rm -f "$tmp"
    fi
    ;;
esac

# ── Chain to repo-specific hook ─────────────────────────────────────
# When core.hooksPath is set globally, git no longer checks .git/hooks/.
# We restore that behavior by forwarding to the repo's hook if present.
git_dir="$(git rev-parse --git-dir 2>/dev/null)"
if [ -n "$git_dir" ]; then
  repo_hook="$git_dir/hooks/$HOOK_NAME"
  if [ -f "$repo_hook" ] && [ -x "$repo_hook" ]; then
    exec "$repo_hook" "$@"
  fi
fi
