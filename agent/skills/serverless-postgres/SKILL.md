---
name: serverless-postgres
description: Design, connect, and troubleshoot managed serverless PostgreSQL with safe connection handling, pooling, branching, migrations, and observability.
---

# Serverless PostgreSQL

Verify the provider's current documentation before recommending a client,
connection mode, pooling setting, or platform limit.

## Connection Rules

- Keep connection strings in environment variables or a secret manager.
- Use pooled connections for bursty serverless workloads and direct
  connections only for operations that require session semantics.
- Require TLS and validate certificates according to the provider contract.
- Bound connect, statement, and transaction timeouts.
- Construct clients once per runtime instance rather than per query.

## Data Safety

- Apply migrations through a single controlled path.
- Test migrations against an isolated branch or disposable database first.
- Use transactions for atomic state changes and make retries idempotent.
- Inspect connection counts, slow queries, locks, storage, and compute usage
  before changing capacity.
- Never print credentials or return production rows in diagnostic output.

For troubleshooting, distinguish DNS, TLS, authentication, pool exhaustion,
statement timeout, transaction conflict, and provider outage. Do not collapse
them into a generic connection error.
