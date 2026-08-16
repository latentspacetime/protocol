---
name: protocol
description: Maintain a protocol registry of durable workflow structure and sync accumulated changes back to the protocol repository as bundled pull requests. Use when the user types /protocol or the bare word proto, or after a session changes shell commands, editor configuration, terminal configuration, git conventions, agent instructions, or skills.
---

# Protocol

A change is protocol level when it alters the durable structure of how the
user works, independent of any single repository, employer, or machine: a
shell command, an editor module, a terminal convention, a git policy, a
harness skill. The test: if this machine were lost, would the change need to
be reproduced on the next one?

The protocol registry is a document in the user's notes or knowledge vault
that inventories every protocol-level item with a category, a canonical
reference, a timestamp, and a sync status against the user's protocol
repository. The user's global agent instructions say where the registry
lives. If none exists, offer to create one with the layout below before doing
anything else.

## Registry Layout

- One table per category (Shell, Editor, Terminal, Git, Agent Harness, and so
  on). Each row: the item, what it is, where it is canonically documented,
  its sync status, and the date last updated.
- A change log, newest first. Each row: timestamp, category, a one-line
  description, and a sync status.
- Sync status vocabulary: `Unsynced` (should be in the repository, is not
  yet), `In PR #N` (bundled into an open pull request), `In repo` (merged),
  `Local by design` (machine- or organization-specific, permanently
  excluded).

## Procedure

1. Read the registry in full. Its own maintenance section is authoritative if
   it and this skill disagree.
2. Identify protocol-level changes from the current session and from any
   recent work the user names. Check shell startup files, the editor and
   terminal configuration directories, the global git ignore, and the harness
   instruction and skill sources.
3. For each change, update the matching registry row and append a change-log
   row with a local timestamp, category, one-line description, and status.
4. Count `Unsynced` change-log rows. Fewer than three: stop and report the
   count. Three or more: continue.
5. Bundle every unsynced item into one pull request to the protocol
   repository:
   - Work from a branch or worktree created from up-to-date `main`, never on
     `main` itself.
   - Generalize each change for any user on any machine: environment
     variables instead of personal paths, neutral wording, no employer or
     client names, no references to the user's private notes, no
     agent-attribution trailers anywhere. Items marked `Local by design`
     never ship.
   - Run the repository's validation and tests; both must pass before
     pushing.
   - Commit under the user's git identity with a plain message, push the
     branch, and open the pull request written as a general improvement to
     the toolkit.
6. Update each bundled registry row from `Unsynced` to `In PR #N`, and to
   `In repo` after the merge.
7. Report what was logged, the unsynced count, and the pull-request link if
   one was opened.
