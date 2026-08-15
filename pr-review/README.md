# Automated PR Review

This guide defines a secure, reusable architecture for model-assisted pull
request review. It intentionally separates portable policy from each target
repository's toolchain and CI graph.

## Threat Model

A pull request is untrusted input. Its code, description, comments, generated
files, and test output can all contain instructions intended to manipulate a
review process. A model that can read this input must not also hold a write
credential.

## Read-Only Review

1. Trigger on `pull_request`, not `pull_request_target`.
2. Skip forks when the selected model requires a repository secret.
3. Checkout full history with `persist-credentials: false`.
4. Give the job `contents: read` and `pull-requests: write` only when a later,
   non-model step must post the result.
5. Pass the PR title, description, base SHA, head SHA, and bounded diff to the
   reviewer.
6. Run the model without shell or write tools.
7. Validate non-empty output and fail when the model command fails.
8. Post or update one comment containing a stable marker and reviewed head SHA.

Independent reviewers should use the same policy but different model families.
Agreement increases confidence; disagreement remains visible for human
judgment.

## Optional Fixer

Automatic fixing needs two jobs:

- **Patch job:** no persisted Git credentials, no write token, bounded tools,
  and an artifact containing only a patch plus a structured report.
- **Apply job:** no model execution. Re-check actor authorization and head SHA,
  validate paths and conflict markers, apply the patch, run trusted validation
  commands, then commit and push.

Do not merge the jobs. Process isolation is the security boundary.

## Authorization

Comment-triggered fixes must query repository permission for the actor and
require `write`, `maintain`, or `admin`. Reject bot accounts, fork pull
requests, stale or closed requests, and requests carrying a disable label.
Add a per-PR concurrency group and a small iteration limit.

## Project Adapter

The target repository owns:

- validation commands and timeouts;
- allowed patch paths;
- generated-file contracts;
- default branch and base-ref policy;
- reviewer identities and comment markers;
- model versions and secret names.

These values must come from the trusted base revision, never from the pull
request branch.

## Rollout

1. Enable read-only reviews.
2. Measure false positives and missed defects.
3. Add structured output and head-SHA binding.
4. Trial patch generation without applying patches.
5. Enable manual, authorized application.
6. Consider automatic application only after the previous stages are stable.
