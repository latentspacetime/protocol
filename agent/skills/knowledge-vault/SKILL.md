---
name: knowledge-vault
description: Organize and maintain a Markdown knowledge vault using canonical documents, controlled metadata, semantic links, generated indexes, and deterministic validation.
---

# Knowledge Vault

Treat Markdown as the canonical store. Indexes, search databases, and reports
are derived views that must be reproducible from it.

## Workflow

1. Read the vault's local rules and index.
2. Search titles, content, tags, and backlinks before creating a document.
3. Update an existing canonical document when the subject and purpose match.
4. Route new material by artifact type: context, decision, runbook, task, or
   inbox.
5. Use controlled tags for broad topics and path-qualified links for specific
   relationships.
6. Explain why important links exist instead of adding bare link lists.
7. Run the vault's validator and regenerate only documented derived views.

## Document Contract

- Use a stable title and matching kebab-case filename.
- Include machine-readable metadata when the vault requires it.
- Start with a short summary that states what the document contains and when
  it is useful.
- Preserve historical evidence; mark superseded documents and link to the
  replacement.
- Keep credentials, private payloads, and generated runtime data out of
  metadata and indexes.

## Quality Bar

One concept has one current owner. Do not add a vector database or graph store
until exact search, summaries, links, and indexing are demonstrably
insufficient. Any retrieval layer must remain disposable and subordinate to
the Markdown source.
