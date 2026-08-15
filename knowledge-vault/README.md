# Knowledge Vault Bootstrap

This directory defines a content-neutral starting point for a local Markdown
knowledge vault. It provides information architecture and validation-friendly
document conventions without including any vault content.

## Layout

```text
Vault/
|-- Context/
|-- Decisions/
|-- Runbooks/
|-- Tasks/
|-- Control/
|-- Inbox/
|-- RULES.md
|-- Index.md
`-- Tags.md
```

Folders classify artifact type. Tags group broad subjects. Links express
specific relationships. The index is a derived navigation surface rather than
the owner of facts.

## Initialize

```zsh
./knowledge-vault/init.zsh "$HOME/Knowledge"
```

The initializer refuses a non-empty destination and never writes outside the
requested root.

## Operating Rules

- Search before creating.
- Keep one current document per concept.
- Record decisions separately from current-state context.
- Use runbooks for repeatable procedures and tasks for execution provenance.
- Route unclassified material to the inbox.
- Keep generated indexes reproducible and disposable.
- Never commit secrets, credentials, or private attachments to a shared
  repository.
