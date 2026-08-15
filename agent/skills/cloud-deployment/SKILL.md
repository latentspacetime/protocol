---
name: cloud-deployment
description: Deploy and operate applications on a managed cloud platform with explicit services, environment references, health checks, logs, metrics, domains, and rollback verification.
---

# Cloud Deployment

Inspect the repository and current platform state before changing
infrastructure. Confirm the target project, environment, service, branch, and
region for every mutation.

## Deployment Contract

- Prefer configuration committed with the application over console-only state.
- Store secrets in the platform and use references instead of copying values.
- Set a health endpoint, startup command, restart policy, and bounded timeout.
- Keep databases and persistent data on managed stores or attached volumes.
- Use preview environments for risky changes and document promotion order.
- Never delete a service, volume, domain, bucket, or environment without an
  explicit request and a reviewed preview.

## Verification

After deployment, check build logs, runtime logs, health status, public routing,
error rate, response-time percentiles, CPU, and memory. Exercise one real
request through the public boundary. If verification fails, diagnose the exact
stage and preserve the last known-good deployment for rollback.
