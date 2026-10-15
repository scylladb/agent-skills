---
title: TTL and Data Expiration
impact: HIGH
impactDescription: Misused TTLs leave partially expired rows, keep expired data on disk, and turn into tombstone-heavy reads
tags: data-modeling, ttl, expiration, default_time_to_live, per-row-ttl, retention
---

## TTL and Data Expiration

**For data with a fixed retention period, set a TTL. Do not delete it with a scheduled `DELETE` job.** A cleanup job writes a tombstone for every row it removes. Expired data still leaves the disk only through compaction (see [tombstones.md](tombstones.md)).

Classic `USING TTL` and `default_time_to_live` behave as in Cassandra. For syntax, collections, counters, and LWT, see [Expiring data with TTL](https://docs.scylladb.com/manual/stable/cql/time-to-live.md). The maximum TTL is 630720000 seconds (20 years). Larger values fail with `ttl is too large`.

### Incorrect: Refreshing the TTL of Some Columns

TTL is stored per cell. `UPDATE ... USING TTL` sets it only on the cells in `SET`.

```
INSERT INTO myapp.sessions (session_id, user_id, last_seen)
VALUES (?, ?, ?) USING TTL 3600;

-- WRONG: tries to "extend the session" by refreshing one column
UPDATE myapp.sessions USING TTL 3600 SET last_seen = ? WHERE session_id = ?;
-- After the first hour user_id and the row marker expire, but last_seen lives on:
-- the row is still returned, with user_id = null.
```

### Correct: Rewrite the Row, or Use Per-Row TTL

```
-- RIGHT (any version): rewrite every column with the new TTL
INSERT INTO myapp.sessions (session_id, user_id, last_seen)
VALUES (?, ?, ?) USING TTL 3600;
```

On ScyllaDB 2026.2 or newer, use [per-row TTL](https://docs.scylladb.com/manual/stable/cql/cql-extensions.md#cql-per-row-ttl), a ScyllaDB CQL extension, when a row's expiry must change independently of its data. One `timestamp` column marked `TTL` holds the absolute expiry time of the whole row:

```
CREATE TABLE myapp.sessions (
    session_id uuid PRIMARY KEY,
    user_id uuid,
    last_seen timestamp,
    expires_at timestamp TTL
);

-- Extend the session without rewriting the row
UPDATE myapp.sessions SET expires_at = ? WHERE session_id = ?;
```

Per-row TTL expiry is **eventual**. A background scan deletes expired rows once per `alternator_ttl_period_in_seconds` (default 86400, 24 hours), and until then the row is still readable. If reads must never return expired rows, also filter on `expires_at` in the application. Unlike `USING TTL`, the expiry appears in CDC as a deletion event.

### Time-Series Data

For append-only time-series data, combine:

- a time bucket in the partition key ([pattern-bucketing.md](pattern-bucketing.md))
- one table-wide `default_time_to_live`, with no per-write overrides
- `TimeWindowCompactionStrategy` ([compaction-strategies.md](compaction-strategies.md))

Then whole SSTables expire together and compaction drops entire files.

### Expired Data Is Still on Disk

Compaction turns expired cells into tombstones, or drops them directly once they pass the table's tombstone GC point ([TTL and compaction facts](https://docs.scylladb.com/manual/stable/kb/ttl-facts.md)). Until then, reads skip over them the same way they skip tombstones. To read recent data, use a lower bound (`AND ts > ?`) so the query does not walk over expired rows.

### When TTL Does Not Apply

- **Data that must be deleted on demand** (a GDPR erasure request, for example): use `DELETE`, and see [tombstones.md](tombstones.md) for the cost.
- **Tables with a vector index**: vector indexes do not support TTL. See the `scylladb-vector-search` skill.
