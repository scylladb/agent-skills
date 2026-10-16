---
title: Compaction Strategies
impact: HIGH
impactDescription: The wrong compaction strategy multiplies disk usage, write I/O, or read latency, and TWCS misuse keeps expired data on disk indefinitely
tags: data-modeling, compaction, ICS, STCS, LCS, TWCS, time-series, disk-space
---

## Compaction Strategies

**Choose the compaction strategy per table, from the workload, when you create the table.** If you set none, ScyllaDB uses `SizeTieredCompactionStrategy` (STCS). ScyllaDB also has `IncrementalCompactionStrategy` (ICS), which Cassandra does not. **Wherever STCS would fit, use ICS**, and replace an explicit `SizeTieredCompactionStrategy` in schemas migrated from Cassandra. ICS has the same amplification as STCS without needing up to 50% free disk during compaction.

| Workload | Strategy |
| --- | --- |
| General purpose, write-heavy, or overwrite-heavy | `IncrementalCompactionStrategy` |
| Read-mostly, few updates | `LeveledCompactionStrategy` (costs ~2x write I/O; avoid for write-heavy tables) |
| Append-only time series with one fixed TTL | `TimeWindowCompactionStrategy` |

For the trade-offs behind this table, see [Choose a compaction strategy](https://docs.scylladb.com/manual/stable/architecture/compaction/compaction-strategies.md). For every option and its default, see [Compaction CQL options](https://docs.scylladb.com/manual/stable/cql/compaction.md).

```
CREATE TABLE myapp.user_profiles (
    user_id uuid PRIMARY KEY,
    name text,
    email text
) WITH compaction = {'class': 'IncrementalCompactionStrategy'};
```

### ICS space amplification goal

Like STCS, ICS can keep overwritten, deleted, and expired data in smaller tiers for a long time. To limit this, set `space_amplification_goal`. When (largest tier + second-largest tier) / largest tier is more than the goal, ICS compacts the two largest tiers together. The option is off by default. See [ICS options](https://docs.scylladb.com/manual/stable/cql/compaction.md#ics-options).

```
ALTER TABLE myapp.user_profiles
  WITH compaction = {'class': 'IncrementalCompactionStrategy',
                     'space_amplification_goal': 1.25};
```

- Use it on update-heavy or overwrite-heavy ICS tables when disk space is the constraint.
- Use a value greater than 1.0 and not more than 2.0.
- Each cross-tier compaction rewrites the largest tier. A lower value triggers it more often and increases write amplification. On a live table, the first one can start soon after the `ALTER`, so get the user's confirmation first.

### TWCS

Use TWCS only when all of these hold. Otherwise use ICS.

- **The table has one `default_time_to_live`, and writes do not override it.** An SSTable drops only when all of its data has expired. ScyllaDB warns when a TWCS table has no `default_time_to_live` (`restrict_twcs_without_default_ttl`).
- **`default_time_to_live / window size` is 50 or less.** `CREATE` and `ALTER TABLE` are rejected above `twcs_max_window_count` (default 50).
- **No `DELETE`, no overwrites, no `USING TIMESTAMP`, no backfill of old data.** Any of these mixes time windows and blocks fully expired SSTables from being dropped. See [TWCS and out-of-order data](https://docs.scylladb.com/manual/stable/kb/compaction.md#time-window-compactionstrategy-twcs).

```
-- WRONG: no default TTL, mixed per-write TTLs, up to 365 one-day windows on disk
CREATE TABLE myapp.metrics (
    sensor_id text, day date, ts timestamp, value double,
    PRIMARY KEY ((sensor_id, day), ts)
) WITH compaction = {'class': 'TimeWindowCompactionStrategy',
                     'compaction_window_unit': 'DAYS',
                     'compaction_window_size': 1};
-- INSERT ... USING TTL 7776000;   -- 90 days for some rows
-- INSERT ... USING TTL 31536000;  -- 1 year for others

-- RIGHT: one 90-day TTL, 3-day windows = 30 windows
CREATE TABLE myapp.metrics (
    sensor_id text, day date, ts timestamp, value double,
    PRIMARY KEY ((sensor_id, day), ts)
) WITH CLUSTERING ORDER BY (ts DESC)
  AND default_time_to_live = 7776000
  AND compaction = {'class': 'TimeWindowCompactionStrategy',
                    'compaction_window_unit': 'DAYS',
                    'compaction_window_size': 3};
```

If data needs two retention periods, use two tables. For a TWCS table that never receives `DELETE`, `tombstone_gc = {'mode': 'immediate'}` lets expired SSTables drop without waiting for repair (see [tombstones.md](tombstones.md)).

### Changing Compaction Options

`ALTER TABLE ... WITH compaction = {...}` **replaces** the whole map. Restate every sub-option you want to keep:

```
-- WRONG: silently resets the window to 1 DAYS
ALTER TABLE myapp.metrics
  WITH compaction = {'class': 'TimeWindowCompactionStrategy', 'tombstone_threshold': 0.3};

-- RIGHT
ALTER TABLE myapp.metrics
  WITH compaction = {'class': 'TimeWindowCompactionStrategy',
                     'compaction_window_unit': 'DAYS',
                     'compaction_window_size': 3,
                     'tombstone_threshold': 0.3};
```

Changing the strategy recompacts the existing data in the background, which is heavy I/O on a large table. Get the user's confirmation before you run it on a live table, and before any `nodetool compact` (major compaction). Major compaction is not routine maintenance. See [How to change compaction strategy](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/config-change/change-compaction.md).
