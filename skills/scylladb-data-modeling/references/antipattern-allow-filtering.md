---
title: "Anti-Pattern: ALLOW FILTERING"
impact: CRITICAL
impactDescription: "Causes full cluster scans — the single most common ScyllaDB performance mistake"
tags: data-modeling, antipattern, allow-filtering, full-scan, performance
---

## Anti-Pattern: ALLOW FILTERING

**`ALLOW FILTERING` forces ScyllaDB to scan every partition in the table.** When a query does not include the full partition key, ScyllaDB cannot determine which node holds the data. Adding `ALLOW FILTERING` tells ScyllaDB to scan ALL nodes and ALL partitions, then filter the results. This has O(N) cost where N is the total data size, regardless of how many rows match.

### Why It's Dangerous

- **Full cluster scan** — every node reads every partition, serializing results back to the coordinator
- **Unpredictable latency** — query time grows linearly with data size: acceptable on 1000 rows, catastrophic on 100 million
- **Resource exhaustion** — a single `ALLOW FILTERING` query can saturate CPU, disk I/O, and memory on all nodes simultaneously
- **Coordinator bottleneck** — one node must collect and merge results from all other nodes

### Incorrect: Query Without Partition Key

```sql
CREATE TABLE orders (
    order_id uuid PRIMARY KEY,
    customer_id uuid,
    status text,
    total decimal,
    created_at timestamp
);

-- WRONG: customer_id is not the partition key
SELECT * FROM orders WHERE customer_id = ? ALLOW FILTERING;
-- Scans every order in the entire table to find ones matching this customer
```

### Correct: Design the Table for the Query

```sql
-- RIGHT: Create a table where customer_id IS the partition key
CREATE TABLE orders_by_customer (
    customer_id uuid,
    created_at timestamp,
    order_id uuid,
    status text,
    total decimal,
    PRIMARY KEY (customer_id, created_at)
) WITH CLUSTERING ORDER BY (created_at DESC);

-- Efficient: goes directly to the correct partition
SELECT * FROM orders_by_customer WHERE customer_id = ?;
```

### Incorrect: Filtering on Non-Primary-Key Columns

```sql
CREATE TABLE products (
    category text,
    product_id uuid,
    name text,
    price decimal,
    in_stock boolean,
    PRIMARY KEY (category, product_id)
);

-- WRONG: in_stock is not in the primary key
SELECT * FROM products WHERE category = 'Electronics' AND in_stock = true ALLOW FILTERING;
-- Even though category (partition key) is specified, filtering on in_stock
-- requires reading every row in the partition and checking in_stock
```

### Correct: Include Filter Columns in the Model

If you frequently filter by `in_stock`, either:

**Option A: Separate table for the query**
```sql
CREATE TABLE in_stock_products_by_category (
    category text,
    in_stock boolean,
    product_id uuid,
    name text,
    price decimal,
    PRIMARY KEY ((category, in_stock), product_id)
);
-- Query: WHERE category = 'Electronics' AND in_stock = true
```

**Option B: Use a secondary index** (acceptable if filter column has moderate cardinality and queries always include the partition key — see `secondary-indexes-and-mv.md`)

### When ALLOW FILTERING Is Acceptable

- **One-time analytics/debug queries** on small tables (< 10,000 rows) that are not in the application's critical path
- **Development/testing** with trivial data volumes
- **Never in production application code** — if you see `ALLOW FILTERING` in application code, it's a data model problem

### Red Flags in Code Review

If you see any of these in application code, investigate:
- `ALLOW FILTERING` in any query string
- A `SELECT` with a `WHERE` clause that doesn't include all partition key columns
- Queries that work in dev but time out in production (data volume grew)
