---
title: Tombstones
impact: HIGH
impactDescription: Tombstone buildup makes reads slow and pages come back empty, and purging tombstones too early resurrects deleted data
tags: data-modeling, tombstones, delete, tombstone_gc, gc_grace_seconds, repair, queue, null
---

## Tombstones

Tombstones come from the same sources as in Cassandra: `DELETE`, expired TTL cells, `null` writes, whole-collection overwrites, and view-key changes in materialized views. Prefer one partition or range delete (`WHERE pk = ? AND ck < ?`) over many row deletes. What differs in ScyllaDB is **when tombstones are purged** and **what reads do when they hit many tombstones**.

### When Tombstones Are Purged

The table's `tombstone_gc` mode controls purging. `gc_grace_seconds` applies only in `timeout` mode. For all modes and options, see [Tombstone GC options](https://docs.scylladb.com/manual/stable/cql/ddl.md#ddl-tombstones-gc).

| Table | Default mode |
| --- | --- |
| Tablets keyspace (default for new keyspaces) | `repair` |
| Vnodes keyspace, ScyllaDB 2026.2 or newer | `repair` |
| Vnodes keyspace, before ScyllaDB 2026.2 | `timeout` (`gc_grace_seconds`, 10 days) |

Colocated tables (CDC log tables, local indexes, and materialized views with the same partition key as the base table, in tablets keyspaces) do not support `repair` mode.

- **In `repair` mode, a table that is never repaired never purges its tombstones.** Run repair on a schedule (ScyllaDB Manager) on every table with RF > 1. With RF = 1, `repair` mode behaves like `immediate`.
- **Use `immediate` only for tables that never receive `DELETE`**, such as append-only TWCS tables with TTL. On a table with deletes it can resurrect data.
- **To clear tombstone buildup, check the mode first** (`DESCRIBE TABLE`). Get the user's confirmation before you change `gc_grace_seconds` or `tombstone_gc` on an existing table, or run major compaction.
  - In `repair` mode, `gc_grace_seconds` has no effect, so do not lower it. Run a repair; the next compaction purges tombstones older than the repair, minus the propagation delay (1 hour by default).
  - In `timeout` mode, do not lower `gc_grace_seconds` without a full repair first ([procedure](https://docs.scylladb.com/manual/stable/kb/gc-grace-seconds.md)). To purge existing tombstones, follow [Flush old tombstones](https://docs.scylladb.com/manual/stable/kb/tombstones-flush.md).

### How Tombstones Affect Reads in ScyllaDB

ScyllaDB has no `tombstone_failure_threshold` and never throws Cassandra's `TombstoneOverwhelmingException`. Instead ([tombstone settings](https://docs.scylladb.com/manual/stable/reference/configuration-parameters.md#confgroup-tombstone-settings)):

- After `query_tombstone_page_limit` tombstones (default 10000), the replica ends the page, **even if the page is empty**. The driver keeps fetching pages, so the query succeeds slowly, in many round trips.
- Application code that treats an empty page as "no more results" stops too early. Iterate the driver's result set, or loop until there is no paging state. Never stop on the first empty page. See [antipattern-unpaged-queries.md](antipattern-unpaged-queries.md).
- A single-partition query that scans more than `tombstone_warn_threshold` tombstones (default 1000) logs a warning on the replica. Look for these warnings when reads on one table are slow.

### Anti-Pattern: Queue Tables

```
-- WRONG: consumers read the oldest rows, then delete them
CREATE TABLE myapp.jobs (
    queue text,
    job_id timeuuid,
    payload text,
    PRIMARY KEY (queue, job_id)
);
SELECT * FROM myapp.jobs WHERE queue = 'email' LIMIT 100;
DELETE FROM myapp.jobs WHERE queue = 'email' AND job_id = ?;
-- Each read scans every deleted job before it reaches a live one.
-- Latency grows with total queue history, not with queue depth.
```

```
-- RIGHT: bucket by time, expire with TTL, and read from a saved position
CREATE TABLE myapp.jobs (
    queue text,
    bucket timestamp,        -- e.g., start of the hour
    job_id timeuuid,
    payload text,
    PRIMARY KEY ((queue, bucket), job_id)
) WITH default_time_to_live = 86400
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_unit': 'HOURS',
                    'compaction_window_size': 1};

SELECT * FROM myapp.jobs
WHERE queue = 'email' AND bucket = ? AND job_id > ?   -- last processed job_id
LIMIT 100;
```

Store the consumer's last processed `job_id` in a small table. The lower bound lets the read start after the consumed rows, and TTL removes old buckets without row deletes. If the workload needs a real queue (acknowledgements, redelivery, many competing consumers), use a message broker.

### Avoid Accidental Tombstones

Bind unset, not `null`, for columns you do not want to write:

```python
# WRONG: writes a tombstone for every missing optional field
session.execute(insert_stmt, (user_id, name, None, None))

# RIGHT: UNSET_VALUE leaves the column untouched (protocol v4+)
from cassandra.query import UNSET_VALUE
session.execute(insert_stmt, (user_id, name, UNSET_VALUE, UNSET_VALUE))
```

The Java driver 4.x leaves unbound values unset. gocql uses `gocql.UnsetValue`. The Rust driver uses `MaybeUnset::Unset`.

Do not overwrite a whole non-frozen collection (`SET tags = {...}`): each overwrite writes a collection tombstone before the new elements. Add or remove elements (`SET tags = tags + {'c'}`) instead. If the application always replaces the whole value, declare the column `frozen<...>`.
