# Global Git Hooks

`dispatch.sh` is a single global hook dispatcher. Every hook name is a symlink
to it; the script decides what to enforce from the name it was invoked as, then
chains to the repository's own `.git/hooks/<name>` so per-repository hooks keep
working even though `core.hooksPath` normally disables them.

The one enforcement currently shipped is on `commit-msg`: it strips AI-agent
attribution lines (co-author trailers naming agent vendors, "Generated with" or
"Built with" footers, and leading robot-emoji lines) from every commit message,
so commits are attributed to their human author only.

## Install

```zsh
mkdir -p ~/.config/git/hooks
cp git-hooks/dispatch.sh ~/.config/git/hooks/dispatch.sh
chmod +x ~/.config/git/hooks/dispatch.sh
for hook in applypatch-msg commit-msg pre-commit prepare-commit-msg \
    pre-push pre-rebase pre-merge-commit pre-applypatch post-applypatch \
    post-checkout post-commit post-merge post-rewrite; do
  ln -sf dispatch.sh ~/.config/git/hooks/$hook
done
git config --global core.hooksPath ~/.config/git/hooks
```

Installation is deliberately manual and opt-in: `install.zsh` does not touch
git hook configuration, because a global `core.hooksPath` affects every
repository on the machine.
