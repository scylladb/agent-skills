---
title: "Pattern: Time Bucketing"
impact: HIGH
impactDescription: "Prevents unbounded partition growth for time-series and event data"
tags: data-modeling, pattern, bucketing, time-series, IoT, partitioning
---

## Pattern: Time Bucketing

**Split unbounded partitions into bounded time buckets by adding a time component to the partition key.** This is the standard solution for time-series data (sensor readings, logs, events, activity feeds) where rows accumulate indefinitely per logical entity.

### The Problem

Without bucketing, all data for an entity goes into one partition forever:

```sql
-- WRONG: Unbounded partition growth
CREATE TABLE sensor_data (
    sensor_id text,
    ts timestamp,
    value double,
    PRIMARY KEY (sensor_id, ts)
);
-- Partition grows indefinitely → eventually OOM on compaction
```

### The Solution

Add a time bucket to the partition key:

```sql
-- RIGHT: Daily buckets
CREATE TABLE sensor_data (
    sensor_id text,
    day date,
    ts timestamp,
    value double,
    PRIMARY KEY ((sensor_id, day), ts)
) WITH CLUSTERING ORDER BY (ts DESC);
```

### Choosing Bucket Size

| Bucket Size | Rows per Bucket (1/sec writes) | Best For |
|-------------|-------------------------------|----------|
| 1 minute | ~60 | Very high write rate per entity (>100/sec) |
| 1 hour | ~3,600 | High write rate (10-100/sec) |
| 1 day | ~86,400 | Moderate write rate (1-10/sec) |
| 1 week | ~604,800 | Low write rate (<1/sec) |
| 1 month | ~2.6M | Very low write rate, small row size |

**Rule of thumb**: Choose the bucket size so each partition stays under 100 MB.

**Calculate**: `partition_size ≈ rows_per_bucket × avg_row_size_bytes`

### Bucket Column Types

```sql
-- Date bucket (daily)
day date,
PRIMARY KEY ((entity_id, day), ts)
-- Application sets: day = toDate(now())

-- Text bucket (flexible granularity)
bucket text,
PRIMARY KEY ((entity_id, bucket), ts)
-- Application sets: bucket = '2024-11-15' or '2024-11-15-14' (hourly) or '2024-W46' (weekly)

-- Integer bucket (epoch-based)
hour_bucket int,
PRIMARY KEY ((entity_id, hour_bucket), ts)
-- Application sets: hour_bucket = unix_timestamp / 3600
```

### Query Patterns

**Single bucket (most common):**
```sql
-- Get today's data for a sensor
SELECT * FROM sensor_data
WHERE sensor_id = 'temp-01' AND day = '2024-11-15';
```

**Range within a bucket:**
```sql
SELECT * FROM sensor_data
WHERE sensor_id = 'temp-01' AND day = '2024-11-15'
  AND ts >= '2024-11-15T10:00:00Z'
  AND ts < '2024-11-15T11:00:00Z';
```

**Multi-bucket query (application-side fan-out):**
```sql
-- Get last 7 days: application issues 7 queries in parallel
-- for day in [today, today-1, today-2, ..., today-6]:
SELECT * FROM sensor_data
WHERE sensor_id = 'temp-01' AND day = ?;
```

Multi-bucket queries require the application to enumerate the bucket values and issue one query per bucket. Use `async` queries or parallel execution for efficiency.

### Data Expiration with TTL

Bucketing pairs well with TTL for automatic data expiration:

```sql
-- Insert with 30-day TTL
INSERT INTO sensor_data (sensor_id, day, ts, value)
VALUES ('temp-01', '2024-11-15', '2024-11-15T10:30:00Z', 22.5)
USING TTL 2592000;  -- 30 days in seconds
```

Or set a table-level default TTL:

```sql
CREATE TABLE sensor_data (
    ...
) WITH default_time_to_live = 2592000;  -- 30 days
```

⚠️ TTL creates tombstones. With time-bucketed data this is typically fine because entire partitions age out together and are compacted away efficiently.

### When NOT to Use Bucketing

- **Bounded data** — if the number of rows per entity is naturally bounded (e.g., max 50 items per order), bucketing adds unnecessary complexity
- **Low-volume entities** — if each entity gets < 1000 rows total over its lifetime, a single partition is fine
- **Random access patterns** — if you never query by time range, the time bucket adds no benefit and complicates queries
