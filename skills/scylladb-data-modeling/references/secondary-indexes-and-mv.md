---
title: "Secondary Indexes and Materialized Views"
impact: MEDIUM
impactDescription: "Enables additional query patterns but with significant trade-offs vs. denormalized tables"
tags: data-modeling, pattern, secondary-index, materialized-view, local-index, global-index
---

## Secondary Indexes and Materialized Views

**ScyllaDB supports secondary indexes (SI), local secondary indexes, and materialized views (MV) to enable additional query patterns without creating fully denormalized tables.** Each comes with trade-offs. In many cases, a denormalized table (query-first design) is the better choice; in many others the engine-maintained view is simpler and just as fast.

### Secondary Indexes (Global)

A global secondary index allows querying a table by a non-primary-key column. ScyllaDB implements this as a hidden materialized view whose partition key is the indexed column, maintained automatically.

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

**How it works**: ScyllaDB creates a hidden view mapping `email → user_id`. A query on `email` first looks up the view (one partition, wherever the base row lives), then fetches the row from the base table. This adds an extra round-trip per query.

**When to use**:
- Point lookups by a non-key column (`email`, `external_id`): the index partition is small and the lookup is two single-partition reads
- Low-to-moderate cardinality filtering combined with the partition key: `WHERE partition_key = ? AND indexed_col = ?`
- Convenience queries that don't justify a separate table

**When NOT to use**:
- Very low-cardinality columns (`status`, `country`) as a global index: the index partition for one value grows without bound (see large partitions)
- The hottest read path in the system — the extra round-trip adds latency; denormalize instead

### Local Secondary Indexes

A local secondary index is scoped to a single partition — it only indexes data within rows that share the same partition key. Queries touch one node, with no fan-out.

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

A materialized view creates a copy of the data with a different primary key, maintained automatically by ScyllaDB on every base write.

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

**How it works**: Every write to the base table triggers an automatic write to the MV, with the same consistency level as the base write. The MV is a full copy of the data with a different partition key. With Raft and tablets, view builds and updates are resumable and consistent across topology changes.

**When to use**:
- You need a different partition key for the same data
- The query pattern is well-defined and stable
- Write amplification is acceptable (each base write ≈ 1 extra write per MV)

**When NOT to use**:
- Very high write throughput where the extra write per MV is the bottleneck
- Many MVs on the same table — write amplification is multiplicative
- Frequently changing MV definition — dropping and recreating a MV requires a full rebuild
- A view whose partition key is low-cardinality (the `status` example above is fine only if the number of orders per status is bounded; otherwise it is a large partition)

### Comparison

| Approach | Read Cost | Write Cost | Consistency | Use Case |
|----------|-----------|------------|-------------|----------|
| Denormalized table | Best (direct lookup) | Application manages writes to multiple tables | Application-level | High-throughput, well-defined queries |
| Local secondary index | Good (single partition) | Low (index maintained automatically) | Automatic | Filtering within a partition |
| Global secondary index | Moderate (two single-partition reads) | Low (index maintained automatically) | Automatic | Point lookups by a non-PK column |
| Materialized view | Good (direct lookup on MV) | One extra write per MV | Automatic (eventual) | Different partition key needed |

### Decision Flow

1. **Can you always provide the partition key?** → Use a local secondary index (if filtering on non-clustering column) or just clustering columns (if the filter column can be a clustering column)
2. **Is the query the hottest path in the system?** → Denormalized table (application-managed writes)
3. **Point lookup by a unique or high-cardinality column?** → Global secondary index
4. **Do you need a completely different partition key with engine-maintained consistency?** → Materialized view (accept write amplification)

### Trade-offs to state plainly

- **Materialized views** are eventually consistent with the base table (the view write follows the base write); reads of the view immediately after a base write may lag by milliseconds. This is the trade-off, not a correctness defect.
- **Secondary indexes** add read latency (extra round-trip to the index + base table)
- **Neither SIs nor MVs** support arbitrary filtering — they optimize for specific column access patterns
- For similarity search over vectors, use a vector index (`scylladb-vector-search`), not a secondary index
