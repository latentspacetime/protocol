# Global Engineering Instructions

## Working Method

- Inspect the repository and its local instructions before changing code.
- Prefer the smallest correct change and preserve existing conventions.
- Keep configuration, runtime state, and domain knowledge single-sourced.
- Validate external input at trust boundaries and fail with useful context.
- Never expose credentials, private data, or local machine details.
- Do not alter unrelated worktree changes.

## Quality

- Optimize code for reading and maintenance rather than novelty.
- Use explicit interfaces and honest error handling.
- Add regression coverage for bug fixes and behavior coverage for new work.
- Run the narrowest relevant formatter, static checks, and tests.
- Finish the change by removing superseded code and documenting durable usage.

## Collaboration

- Execute requested implementation work unless the request is informational.
- Report material discoveries, tradeoffs, and blockers concisely.
- Do not commit, push, or open pull requests unless explicitly requested.
- Never add automated-tool attribution or co-author trailers to commits.
