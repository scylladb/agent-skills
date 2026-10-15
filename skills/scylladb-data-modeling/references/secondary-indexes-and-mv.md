---
title: "Secondary Indexes and Materialized Views"
impact: MEDIUM
impactDescription: "Enables additional query patterns but with significant trade-offs vs. denormalized tables"
tags: data-modeling, pattern, secondary-index, materialized-view, local-index, global-index
---

## Secondary Indexes and Materialized Views

**ScyllaDB supports secondary indexes (SI), local secondary indexes, and materialized views (MV) to enable additional query patterns without creating fully denormalized tables.** However, each comes with significant trade-offs. In many cases, a denormalized table (query-first design) is the better choice.

### Secondary Indexes (Global)

A global secondary index allows querying a table by a non-primary-key column. ScyllaDB implements this as a hidden table maintained automatically.

```sql
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    email text,
    name text,
    country text
);

-- Create a secondary index on email
CREATE INDEX ON users (email);

-- Now you can query by email
SELECT * FROM users WHERE email = 'alice@example.com';
```

**How it works**: ScyllaDB creates a hidden materialized view whose partition key is the indexed column (`email`) and whose clustering key is the base table's primary key. A query on `email` first reads the one index partition for that value to find the `user_id`, then fetches the row from the base table. This adds an extra round-trip per query. See the [Global Secondary Indexes docs](https://docs.scylladb.com/manual/stable/features/secondary-indexes.md).

Because the index is partitioned by the indexed value, the partition-key rules from `partition-key-design.md` apply to the indexed column. This is the opposite of the Cassandra (2i) rule of thumb.

**When to use**:
- High-cardinality columns where each value matches few rows (e.g., `email`, `username`, `order_number`)
- Queries without the partition key that look up by a non-primary-key column
- Convenience queries that don't justify a separate table

**When NOT to use**:
- Low-cardinality columns (e.g., `status`, `country`, booleans) — all rows with the same value land in ONE index partition on one replica set, creating a large, hot index partition. Use a local index (if the partition key is known) or a bucketed denormalized table instead
- High-throughput queries — the extra round-trip adds latency
- High write throughput — every base write also updates the hidden view, usually on a different node

### Local Secondary Indexes

A local secondary index is scoped to a single partition — it only indexes data within rows that share the same partition key. This makes queries much faster than global indexes because only one node is involved.

```sql
CREATE TABLE orders (
    customer_id uuid,
    order_date date,
    order_id uuid,
    status text,
    total decimal,
    PRIMARY KEY (customer_id, order_date, order_id)
);

-- Local index on status, scoped to customer_id partition
CREATE INDEX ON orders ((customer_id), status);

-- Efficient: searches only within the customer's partition
SELECT * FROM orders WHERE customer_id = ? AND status = 'shipped';
```

**When to use**:
- Filtering within a partition on a non-clustering column
- When the partition key is always specified in the query
- Moderate cardinality columns within a partition

### Materialized Views

A materialized view creates a full copy of the data with a different primary key, maintained automatically by ScyllaDB.

```sql
-- Base table: orders by customer
CREATE TABLE orders (
    customer_id uuid,
    order_id uuid,
    status text,
    total decimal,
    created_at timestamp,
    PRIMARY KEY (customer_id, created_at, order_id)
);

-- Materialized view: orders by status
CREATE MATERIALIZED VIEW orders_by_status AS
    SELECT * FROM orders
    WHERE status IS NOT NULL AND customer_id IS NOT NULL
      AND created_at IS NOT NULL AND order_id IS NOT NULL
    PRIMARY KEY (status, created_at, order_id);
```

**How it works**: Every write to the base table triggers an automatic write to the MV. The MV is a full copy of the data with a different partition key.

**When to use**:
- You need a different partition key for the same data
- The query pattern is well-defined and stable
- Write amplification is acceptable (each base write ≈ 1 extra write per MV)

**When NOT to use**:
- High write throughput — each MV doubles write cost
- Multiple MVs on the same table — write amplification is multiplicative
- Frequently changing MV definition — dropping and recreating a MV requires a full rebuild

### Comparison

| Approach | Read Cost | Write Cost | Consistency | Use Case |
|----------|-----------|------------|-------------|----------|
| Denormalized table | Best (direct lookup) | Application manages writes to multiple tables | Application-level | High-throughput, well-defined queries |
| Local secondary index | Good (single partition) | Low (index maintained automatically) | Automatic | Filtering within a partition |
| Global secondary index | Moderate (index lookup + base-table read) | Moderate (hidden view updated on each write) | Automatic (eventual) | Lookups by a high-cardinality non-PK column |
| Materialized view | Good (direct lookup on MV) | High (full data copy per MV) | Automatic (eventual) | Different partition key needed, moderate write rate |

### Decision Flow

1. **Can you always provide the partition key?** → Use a local secondary index (if filtering on non-clustering column) or just clustering columns (if the filter column can be a clustering column)
2. **Is the query high-throughput?** → Denormalized table (application-managed writes)
3. **Is the query low-frequency / convenience, on a high-cardinality column?** → Global secondary index
4. **Do you need a completely different partition key with automatic consistency?** → Materialized view (accept write amplification)

### ⚠️ Known Limitations

- **Materialized views** are eventually consistent with the base table: a write to the base table updates the view asynchronously, so a read from the view can briefly return stale data. When a query must see its own writes immediately, prefer application-managed denormalization with explicit writes to multiple tables
- **Secondary indexes** add read latency (extra round-trip to index table + base table)
- **Neither SIs nor MVs** support arbitrary filtering — they optimize for specific column access patterns
