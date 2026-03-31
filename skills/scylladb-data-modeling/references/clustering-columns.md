---
title: "Clustering Columns"
impact: HIGH
impactDescription: "Controls sort order within partitions, enables range queries and efficient time-series access"
tags: data-modeling, fundamentals, clustering-columns, sort-order, range-queries, time-series
---

## Clustering Columns

**Clustering columns define the sort order of rows within a partition.** They are the columns after the partition key in the `PRIMARY KEY` definition. Rows within a partition are physically stored in sorted order by their clustering columns, making range queries on those columns extremely efficient.

### How Clustering Columns Work

```sql
CREATE TABLE messages (
    conversation_id uuid,
    sent_at timestamp,
    message_id uuid,
    body text,
    PRIMARY KEY (conversation_id, sent_at, message_id)
) WITH CLUSTERING ORDER BY (sent_at DESC, message_id ASC);
```

- `conversation_id` — partition key (determines which node/shard)
- `sent_at` — first clustering column (rows sorted by timestamp, descending)
- `message_id` — second clustering column (tiebreaker when timestamps are equal)

Rows within a partition are stored on disk in this sorted order, so reading them in order requires no additional sorting.

### Supported Query Patterns

Given `PRIMARY KEY ((pk), ck1, ck2, ck3)`:

| Query WHERE clause | Supported? | Notes |
|-------------------|------------|-------|
| `pk = ?` | ✅ | Returns all rows in partition, in clustering order |
| `pk = ? AND ck1 = ?` | ✅ | Narrows to a slice of the partition |
| `pk = ? AND ck1 = ? AND ck2 = ?` | ✅ | Narrows further |
| `pk = ? AND ck1 > ?` | ✅ | Range query on first clustering column |
| `pk = ? AND ck1 = ? AND ck2 > ?` | ✅ | Range on second, equality on first |
| `pk = ? AND ck2 = ?` | ❌ | Skipping ck1 requires `ALLOW FILTERING` |
| `pk = ? AND ck1 > ? AND ck2 = ?` | ❌ | Equality after range requires `ALLOW FILTERING` |

**Rule: clustering columns must be specified in order, left to right. You can switch from equality to range at most once.**

### Clustering Order

```sql
-- Default: ASC for all clustering columns
CREATE TABLE events (
    sensor_id text,
    event_time timestamp,
    event_id uuid,
    data text,
    PRIMARY KEY (sensor_id, event_time)
);
-- Equivalent to: WITH CLUSTERING ORDER BY (event_time ASC)

-- Override: newest first
CREATE TABLE events_desc (
    sensor_id text,
    event_time timestamp,
    event_id uuid,
    data text,
    PRIMARY KEY (sensor_id, event_time)
) WITH CLUSTERING ORDER BY (event_time DESC);
```

**Choose the clustering order that matches your most common query's `ORDER BY`.** Reading in the natural storage order is a sequential scan (fast). Reading in reverse order is also supported but can be slightly less efficient.

### Incorrect: No Clustering for Time-Series

```sql
-- WRONG: Each reading is its own partition
CREATE TABLE sensor_readings (
    sensor_id text,
    reading_time timestamp,
    value double,
    PRIMARY KEY ((sensor_id, reading_time))
);
-- Cannot do range queries: WHERE sensor_id = ? AND reading_time > ?
-- Every single reading is a separate partition
```

### Correct: Time as Clustering Column

```sql
-- RIGHT: Readings clustered by time within each sensor+day partition
CREATE TABLE sensor_readings (
    sensor_id text,
    day date,
    reading_time timestamp,
    value double,
    PRIMARY KEY ((sensor_id, day), reading_time)
) WITH CLUSTERING ORDER BY (reading_time DESC);

-- Efficient range query within a day:
SELECT * FROM sensor_readings
WHERE sensor_id = 'temp-01' AND day = '2024-11-15'
  AND reading_time >= '2024-11-15T10:00:00Z'
  AND reading_time < '2024-11-15T11:00:00Z';
```

### Multiple Clustering Columns

Use multiple clustering columns for hierarchical data within a partition:

```sql
CREATE TABLE products_by_category (
    category text,
    subcategory text,
    product_name text,
    price decimal,
    PRIMARY KEY (category, subcategory, product_name)
);

-- Get all products in a category: WHERE category = 'Electronics'
-- Get all in a subcategory: WHERE category = 'Electronics' AND subcategory = 'Phones'
-- Get a specific product: WHERE category = 'Electronics' AND subcategory = 'Phones' AND product_name = 'Galaxy S24'
```

### When NOT to Use Clustering Columns

- **Single-row lookups** — if every query retrieves exactly one row by its full key, clustering adds no benefit; use a simple `PRIMARY KEY (id)`
- **Random access patterns** — if you never query ranges or ordered subsets, clustering order doesn't matter
