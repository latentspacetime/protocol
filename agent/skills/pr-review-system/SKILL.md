---
name: pr-review-system
description: Design or install automated pull-request review and optional fixing with read-only reviewers, explicit authorization, credential isolation, bounded execution, and project-specific validation.
---

# PR Review System

Read `pr-review/README.md` in this repository before implementing a workflow.

## Required Architecture

- Review jobs run on `pull_request`, reject fork pull requests when secrets are
  required, and receive read-only repository credentials.
- Checkouts used by a model set `persist-credentials: false`.
- The model process never receives a token with repository write access.
- Review comments identify the reviewed head SHA and are upserted by a stable
  marker.
- A clean review is distinguishable from an actionable finding.
- All API listing operations paginate or enforce a documented bound.

## Fixer Boundary

A fixer is optional. If enabled:

1. Verify the triggering actor has repository write permission.
2. Reject bot triggers, closed pull requests, forks, and disabled labels.
3. Serialize runs with a per-pull-request concurrency group.
4. Generate a patch in an uncredentialed job.
5. Validate the patch and reject paths outside the approved diff scope.
6. Apply and push from a separate job that never executes model-controlled
   commands.
7. Bound iterations and stop on validation failure or stale head SHA.

Never give an unrestricted model process a persisted Git credential. Never
turn model failure into success with `|| true`, and never commit unresolved
conflict markers.

## Repository Adapter

Keep these values in the target repository, not in shared workflow logic:

- default and protected branches;
- language toolchains;
- formatting, lint, build, and test commands;
- generated-file checks;
- model names and review thresholds;
- secrets and identity allowlists.

Test the workflow on a disposable branch with one deliberate defect and one
clean change before enabling automatic fixes.
