---
title: Query Protection and Aggregates
impact: HIGH
impactDescription: "Knobs that keep one bad access pattern from taking the cluster down, plus server-side aggregates"
tags: rate-limit, per-partition-rate-limit, bypass-cache, timeout, using-timeout, hot-partition, aggregates, count, heat-weighted-load-balancing
---

## Query Protection

### Per-partition rate limit

Stops bots, hot keys and retry storms from flooding one partition. The cap is per partition, per table; requests beyond it fail fast with an error the driver can retry or drop.

```sql
ALTER TABLE app.sessions WITH per_partition_rate_limit = {'max_reads_per_second': 1000, 'max_writes_per_second': 200};
```

Use it as the immediate fix for a hot-partition incident while the schema is redesigned (see `scylladb-data-modeling`, hot partitions). Counting is approximate and per shard; set limits with margin.

### BYPASS CACHE

Keeps a large scan or an analytics query from evicting the OLTP working set from the row cache.

```sql
SELECT * FROM app.events WHERE day = ? BYPASS CACHE;
```

Add it to any full-table or large-range read that is not latency-sensitive. Pair it with a batch service level (see `workload-prioritization.md`).

### Timeouts

```sql
SELECT * FROM app.users WHERE id = ? USING TIMEOUT 50ms;
INSERT INTO app.events (...) VALUES (...) USING TIMEOUT 200ms;
```

Precedence: `USING TIMEOUT` > the role's service level timeout > cluster default. Set the shortest timeout the application can retry; a 20 ms timeout on an interactive path is normal.

### Heat-weighted load balancing (automatic)

A restarted or newly added node receives a growing share of reads as its cache warms, so rolling restarts and upgrades do not spike latency. Nothing to configure; worth knowing when a user asks why a restarted node "gets less traffic".

### Distributed aggregates

`SELECT COUNT(*)`, `SUM`, `AVG`, `MIN`, `MAX` over a table or partition are split per token range, executed on every shard in parallel and reduced at the coordinator. A full-table count on terabytes takes seconds. Do not tell users to count client-side.

```sql
SELECT COUNT(*) FROM app.events BYPASS CACHE USING TIMEOUT 120s;
SELECT AVG(value) FROM app.metrics WHERE sensor_id = ? AND day = ?;
```

Docs: https://docs.scylladb.com/manual/stable/cql/ddl.html (per-partition rate limit), https://docs.scylladb.com/manual/stable/cql/dml.html (BYPASS CACHE, USING TIMEOUT)
