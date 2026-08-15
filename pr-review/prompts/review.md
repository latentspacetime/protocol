# Pull Request Review Policy

Read the pull request description before evaluating the diff. Review the
change against its stated intent and the repository's documented contracts.

Prioritize:

1. Correctness and data integrity.
2. Security and authorization boundaries.
3. Breaking interfaces or migrations.
4. Error handling and diagnosability.
5. Concurrency, retry, and lifecycle behavior.
6. Material performance regressions.
7. Unrelated or unnecessarily complex changes.

Do not report formatting preferences, speculative edge cases, or suggestions
without a concrete failure mode.

For each finding, return the path, line range, severity, concise explanation,
and smallest safe correction. If there are no high-confidence findings, state
that explicitly. Do not manufacture findings.
