---
title: Prepared Statements
impact: HIGH
impactDescription: Required for token-aware shard routing; reduces per-query parsing overhead
tags: cloud-setup, performance, prepared-statements, token-aware-routing
---

## Prepared Statements

An unprepared (simple) statement is parsed and planned by the coordinator on every execution. A prepared statement is parsed once, cached, and subsequent executions send only the statement ID and bound values. Beyond the parsing cost, prepared statements are required for ScyllaDB's shard-aware, token-aware routing to work correctly: the driver can only compute which shard owns a given partition key if it knows the statement's parameter types and positions in advance, which requires preparation.

### Incorrect

```
session.execute(f"SELECT * FROM users WHERE user_id = {user_id}")
# Parsed fresh every call. Also shaped like a SQL-injection anti-pattern
# in any language where this string is built from user input.
```

### Correct

```
prepared = session.prepare("SELECT * FROM users WHERE user_id = ?")
session.execute(prepared, [user_id])
# Prepare once (e.g. at startup or on first use, caching the
# PreparedStatement object), then bind and execute repeatedly.
```

### When Not to Bother

One-off administrative or debug queries run a single time are not worth preparing. Anything executed more than a handful of times, or executed inside a request-handling path, should be prepared.
