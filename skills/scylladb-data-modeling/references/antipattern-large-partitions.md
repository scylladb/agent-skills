---
title: Anti-Pattern: Large Partitions
impact: CRITICAL
impactDescription: Causes slow reads, slow repair and uneven shard load
tags: data-modeling, antipattern, large-partitions, unbounded-growth, compaction, repair, hot-shard
---

## Anti-Pattern: Large Partitions

**Partitions that grow without bounds are the second most common ScyllaDB performance issue.** When a partition exceeds ~100 MB, reads of it get slower, repair and streaming become coarse-grained (a partition is the unit), and the single shard that owns it carries a disproportionate share of the table's load.

Note on a common misconception: ScyllaDB does **not** need to hold a whole partition in memory during compaction or reads; it streams partitions row by row. Large partitions do not cause compaction OOMs in ScyllaDB the way they did in older Cassandra. The costs below are the real ones.

### Why It's Dangerous

- **Slow reads** — a read must merge the partition's rows from several SSTables and the memtable; the more rows in one partition, the more work per read, and the row cache holds less of it
- **Hot shard** — one partition lives on one shard per replica; a huge partition concentrates reads, writes and compaction on that shard while the rest of the node idles
- **Coarse repair and streaming** — repair and tablet migration work in partition units; one huge partition is one indivisible unit of work
- **Tombstone accumulation** — deletes and TTL expiry inside a large partition pile up tombstones that every read must skip until compaction removes them

Automatic handling of oversized partitions is on the ScyllaDB roadmap; until it ships, bound partitions by design.

### Incorrect: Unbounded Time-Series Partition

```
-- WRONG: All readings for a sensor go into ONE partition forever
CREATE TABLE sensor_readings (
    sensor_id text,
    reading_time timestamp,
    value double,
    PRIMARY KEY (sensor_id, reading_time)
);
-- A sensor that reports every second generates 86,400 rows/day → 31.5M rows/year
-- Partition grows indefinitely → ever slower reads, one hot shard
```

### Correct: Bucket by Time

```
-- RIGHT: Add a time bucket to the partition key
CREATE TABLE sensor_readings (
    sensor_id text,
    day date,          -- bucket: one partition per sensor per day
    reading_time timestamp,
    value double,
    PRIMARY KEY ((sensor_id, day), reading_time)
) WITH CLUSTERING ORDER BY (reading_time DESC);

-- Each partition holds at most 86,400 rows (one day of per-second data)
-- Predictable, bounded partition size
```

See `pattern-bucketing.md` for detailed bucketing strategies. For time series, pair bucketing with TTL and `TimeWindowCompactionStrategy` (see the `scylladb-features` skill, compaction reference).

### Incorrect: Unbounded User Activity

```
-- WRONG: All activity for a user in one partition
CREATE TABLE user_activity (
    user_id uuid,
    activity_time timestamp,
    activity_type text,
    details text,
    PRIMARY KEY (user_id, activity_time)
);
-- Power users can generate millions of activity records
-- Partition grows without bound
```

### Correct: Bucket User Activity

```
-- RIGHT: Bucket by month
CREATE TABLE user_activity (
    user_id uuid,
    month text,        -- e.g., '2024-11'
    activity_time timestamp,
    activity_type text,
    details text,
    PRIMARY KEY ((user_id, month), activity_time)
) WITH CLUSTERING ORDER BY (activity_time DESC);
```

### Sizing Rules of Thumb

| Rows per Partition | Row Size | Partition Size | Risk              |
| ------------------- | -------- | -------------- | ------------------ |
| < 100,000           | < 1 KB   | < 100 MB       | Safe                |
| 100K – 1M           | < 1 KB   | 100 MB – 1 GB  | Monitor             |
| > 1M                | Any      | > 1 GB         | Redesign needed     |
| Any                 | > 10 KB  | > 100 MB       | Monitor             |

Note: 100 MB is a design target, not ScyllaDB's current system default. The scylla.yaml parameter that controls ScyllaDB's own large-partition warning, compaction_large_partition_warning_threshold_mb, currently defaults to 1000 MB. Designing to the stricter 100 MB target leaves headroom before the system's own warning would fire, and is a better guide for schema design than the configured default itself.

### How to Detect

```
# Check partition size distribution
nodetool tablehistograms <keyspace>.<table>
# Look at "Partition Size" percentiles
# p99 > 100 MB → investigate

# Check for large partitions in logs
grep "large_partition" /var/log/syslog
# ScyllaDB logs warnings when partitions exceed the configured threshold

# In ScyllaDB Monitoring: a single shard with much higher load than its peers
# on the same node is the signature of a large or hot partition
```

### When Large Partitions Are Acceptable

- **Static or slowly growing data** — e.g., a `users` table where each user has a bounded number of attributes
- **Known bounded cardinality** — e.g., a maximum of 50 items per order, enforced by application logic
- **Read-rarely data** — if the partition is large but almost never read, the cost may be tolerable
