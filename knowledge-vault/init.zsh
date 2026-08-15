#!/bin/zsh

set -eu
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:${PATH:-}"

if (( $# != 1 )); then
  print -u2 "usage: $0 <vault-directory>"
  exit 2
fi

vault_root="${1:A}"
if [[ -e "$vault_root" && -n "$(ls -A "$vault_root" 2>/dev/null)" ]]; then
  print -u2 "refusing non-empty destination: $vault_root"
  exit 1
fi

mkdir -p "$vault_root"/{Context,Decisions,Runbooks,Tasks,Control,Inbox}

cat > "$vault_root/RULES.md" <<'EOF'
# Vault Rules

- Search before creating a document.
- Keep one canonical current-state source per concept.
- Use folders for artifact type, tags for broad topics, and links for specific relationships.
- Treat indexes and reports as derived views.
- Keep secrets and private payloads out of metadata and generated views.
EOF

cat > "$vault_root/Tags.md" <<'EOF'
# Controlled Tags

Add a tag only when several documents need the distinction. Prefer stable domains and concerns over temporary status labels.
EOF

cat > "$vault_root/Index.md" <<'EOF'
# Vault Index

This index is reserved for generated navigation. Do not store unique facts here.
EOF

print "initialized knowledge vault at $vault_root"
