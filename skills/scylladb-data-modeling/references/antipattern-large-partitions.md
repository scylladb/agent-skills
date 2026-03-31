---
title: "Anti-Pattern: Large Partitions"
impact: CRITICAL
impactDescription: "Causes OOM during compaction, slow reads, and uneven disk usage"
tags: data-modeling, antipattern, large-partitions, unbounded-growth, compaction, OOM
---

## Anti-Pattern: Large Partitions

**Partitions that grow without bounds are the second most common ScyllaDB performance issue.** When a partition exceeds ~100 MB, reads become slow, compaction requires more memory, and repair operations take longer. At ~1 GB+, you risk Out-Of-Memory (OOM) crashes during compaction because the entire partition must fit in memory.

### Why It's Dangerous

- **Memory during compaction** — ScyllaDB must hold the entire partition in memory during compaction. A 2 GB partition can cause OOM
- **Slow reads** — reading a large partition requires scanning many SSTables and merging data in memory
- **Slow repairs** — repair operates at the partition level; repairing one huge partition blocks other work
- **Uneven disk usage** — a few massive partitions can fill one node's disk while others have space

### Incorrect: Unbounded Time-Series Partition

```sql
-- WRONG: All readings for a sensor go into ONE partition forever
CREATE TABLE sensor_readings (
    sensor_id text,
    reading_time timestamp,
    value double,
    PRIMARY KEY (sensor_id, reading_time)
);
-- A sensor that reports every second generates 86,400 rows/day → 31.5M rows/year
-- Partition grows indefinitely → eventually OOM on compaction
```

### Correct: Bucket by Time

```sql
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

See `pattern-bucketing.md` for detailed bucketing strategies.

### Incorrect: Unbounded User Activity

```sql
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

```sql
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

| Rows per Partition | Row Size | Partition Size | Risk |
|-------------------|----------|----------------|------|
| < 100,000 | < 1 KB | < 100 MB | ✅ Safe |
| 100K – 1M | < 1 KB | 100 MB – 1 GB | ⚠️ Monitor |
| > 1M | Any | > 1 GB | ❌ Redesign needed |
| Any | > 10 KB | > 100 MB | ⚠️ Monitor |

### How to Detect

```bash
# Check partition size distribution
nodetool tablehistograms <keyspace>.<table>
# Look at "Partition Size" percentiles
# p99 > 100 MB → investigate

# Check for large partitions in logs
grep "large_partition" /var/log/syslog
# ScyllaDB logs warnings when partitions exceed the configured threshold
```

### When Large Partitions Are Acceptable

- **Static or slowly growing data** — e.g., a `users` table where each user has a bounded number of attributes
- **Known bounded cardinality** — e.g., a maximum of 50 items per order, enforced by application logic
- **Read-rarely data** — if the partition is large but almost never read, the compaction cost may be tolerable
