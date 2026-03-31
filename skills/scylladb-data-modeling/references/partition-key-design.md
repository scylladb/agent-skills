---
title: "Partition Key Design"
impact: CRITICAL
impactDescription: "Determines data distribution, query capability, and cluster balance"
tags: data-modeling, fundamentals, partition-key, composite-key, distribution, cardinality
---

## Partition Key Design

**The partition key determines which node and shard holds your data.** It is the most critical design decision in a ScyllaDB table. A poor partition key causes hot spots, large partitions, or queries that require table scans.

### Rules

1. **Every `SELECT` must include the full partition key in the `WHERE` clause** — without it, ScyllaDB must scan every node (requires `ALLOW FILTERING`)
2. **High cardinality** — the partition key should have many distinct values to distribute data evenly across the cluster
3. **Even distribution** — no single partition key value should receive a disproportionate share of reads or writes
4. **Right granularity** — too fine (one row per partition) wastes clustering column benefits; too coarse (millions of rows per partition) creates large partitions

### Simple Partition Key

A single column as the partition key:

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    email text
);
-- partition key: user_id
-- No clustering columns
-- One row per partition
```

Best when: each entity is accessed individually by its ID.

### Composite Partition Key

Multiple columns form the partition key (wrapped in extra parentheses):

```sql
CREATE TABLE sensor_readings (
    sensor_id text,
    day date,
    reading_time timestamp,
    value double,
    PRIMARY KEY ((sensor_id, day), reading_time)
) WITH CLUSTERING ORDER BY (reading_time DESC);
```

- Partition key: `(sensor_id, day)` — data for one sensor on one day lives in one partition
- Clustering column: `reading_time` — readings sorted newest-first within each partition
- Query: `SELECT * FROM sensor_readings WHERE sensor_id = ? AND day = ?`

This is a **bucketing** pattern — each partition is bounded to one day's data for one sensor.

### Incorrect: Low-Cardinality Partition Key

```sql
-- WRONG: Only a few distinct values → hot partitions
CREATE TABLE events (
    event_type text,
    event_time timestamp,
    data text,
    PRIMARY KEY (event_type, event_time)
);
-- If event_type has 5 values, ALL data goes to 5 partitions
-- 5 nodes/shards do all the work, rest of cluster is idle
```

### Correct: Add Cardinality

```sql
-- RIGHT: Add a bucketing dimension for cardinality
CREATE TABLE events (
    event_type text,
    bucket int,          -- e.g., hash(event_id) % 100
    event_time timestamp,
    event_id uuid,
    data text,
    PRIMARY KEY ((event_type, bucket), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
-- 5 event types × 100 buckets = 500 partitions → well distributed
```

Trade-off: queries for a single `event_type` now require reading up to 100 partitions (fan-out). Choose the bucket count based on your write rate vs. read pattern.

### Choosing the Right Partition Key

| Access Pattern | Partition Key | Why |
|---------------|--------------|-----|
| Lookup by user | `user_id` | 1:1 mapping |
| Messages in a conversation | `conversation_id` | All messages together |
| Sensor data (time-series) | `(sensor_id, day)` | Bounded daily partitions |
| Events by type (high volume) | `(event_type, bucket)` | Distribute high-volume types |
| Multi-tenant SaaS | `(tenant_id, entity_id)` | Isolate tenants |

### Partition Size Guidelines

- **Target**: 100 MB or less per partition
- **Soft warning**: > 100 MB — queries may become slower, compaction takes longer
- **Hard trouble**: > 1 GB — risk of OOM during compaction, query timeouts
- Monitor with `nodetool tablehistograms <keyspace>.<table>` — check the partition size percentiles

### Verify Partition Key Distribution

```sql
-- Check the token distribution for a sample of rows
SELECT token(partition_key_col), partition_key_col FROM my_table LIMIT 100;
```

Tokens should be spread across the full token range (`-2^63` to `+2^63`). If many rows cluster around a few token values, the partition key has low cardinality.
