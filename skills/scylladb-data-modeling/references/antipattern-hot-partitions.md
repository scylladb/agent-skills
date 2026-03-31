---
title: "Anti-Pattern: Hot Partitions"
impact: HIGH
impactDescription: "Causes uneven load distribution — some nodes/shards are overloaded while others sit idle"
tags: data-modeling, antipattern, hot-partitions, load-distribution, cardinality, sharding
---

## Anti-Pattern: Hot Partitions

**A hot partition occurs when a disproportionate amount of traffic hits the same partition key.** Because each partition lives on a specific node and shard, a hot partition overloads one CPU core while the rest of the cluster is idle. ScyllaDB's shard-per-core architecture makes this especially visible — a hot shard maxes out at 100% of one core regardless of how many other cores are available.

### Why It's Dangerous

- **Single-shard bottleneck** — one shard handles all traffic for the hot partition while others are underutilized
- **Cannot be fixed by scaling** — adding more nodes doesn't help if all traffic still goes to one partition
- **Cascading latency** — other queries routed to the same node/shard are delayed behind the hot partition's traffic
- **Misleading metrics** — average cluster utilization looks low while one shard is at 100%

### Incorrect: Low-Cardinality Partition Key

```sql
-- WRONG: Only a handful of distinct status values
CREATE TABLE orders_by_status (
    status text,
    created_at timestamp,
    order_id uuid,
    total decimal,
    PRIMARY KEY (status, created_at)
);
-- status has ~5 values: 'pending', 'processing', 'shipped', 'delivered', 'cancelled'
-- 'pending' gets 80% of writes → one partition is massively hot
```

### Correct: Add Bucketing for Distribution

```sql
-- RIGHT: Distribute across more partitions
CREATE TABLE orders_by_status (
    status text,
    bucket int,          -- hash(order_id) % 64
    created_at timestamp,
    order_id uuid,
    total decimal,
    PRIMARY KEY ((status, bucket), created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);
-- 5 statuses × 64 buckets = 320 partitions → even distribution
-- Trade-off: reading all 'pending' orders requires 64 parallel queries
```

### Incorrect: Timestamp-Based Partition Key

```sql
-- WRONG: All writes for "now" go to the same partition
CREATE TABLE events (
    event_date date,
    event_time timestamp,
    event_id uuid,
    data text,
    PRIMARY KEY (event_date, event_time)
);
-- Today's partition gets ALL writes. Yesterday's gets none.
-- This is both a hot partition AND a large partition problem.
```

### Correct: Distribute Within the Time Window

```sql
-- RIGHT: Spread today's writes across multiple partitions
CREATE TABLE events (
    event_date date,
    shard int,           -- e.g., hash(event_id) % 256
    event_time timestamp,
    event_id uuid,
    data text,
    PRIMARY KEY ((event_date, shard), event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
-- 256 partitions per day → writes distributed evenly
```

### Incorrect: Global Counter

```sql
-- WRONG: Every increment hits the same partition
CREATE TABLE page_views (
    page_id text PRIMARY KEY,
    view_count counter
);
-- The home page gets millions of increments → one partition handles everything
```

### Correct: Distributed Counter with Shards

```sql
-- RIGHT: Shard the counter
CREATE TABLE page_views (
    page_id text,
    shard int,           -- 0..N
    view_count counter,
    PRIMARY KEY (page_id, shard)
);
-- Write: increment a random shard
-- Read: SELECT SUM(view_count) WHERE page_id = ? (application-side aggregation)
```

### How to Detect Hot Partitions

```bash
# Check per-shard CPU utilization
# In ScyllaDB Monitoring, look for:
# - Uneven CPU utilization across shards on the same node
# - One shard consistently higher than others

# Check write latency per shard
# Large variance between shards suggests uneven load
```

In ScyllaDB Cloud, use the **Monitoring** tab to check per-node metrics. If one node consistently shows higher CPU/latency than others, suspect a hot partition.

### When Hot Partitions Are Acceptable

- **Read-heavy, small hot data** — e.g., a frequently read configuration row that fits in cache. Reads from cache are fast and don't cause the same problems as write-heavy hot partitions
- **Temporary spikes** — a partition that's hot during a brief event (e.g., flash sale) but not sustained
