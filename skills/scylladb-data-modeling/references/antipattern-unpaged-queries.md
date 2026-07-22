---
title: Anti-Pattern: Unpaged Queries
impact: CRITICAL
impactDescription: Unbounded result sets cause cluster-wide memory pressure, timeouts, and node instability
tags: data-modeling, antipattern, paging, fetch-size, memory
---

## Anti-Pattern: Unpaged Queries

A SELECT without paging asks the coordinator to assemble the entire result set before returning anything to the client. On a small table this is invisible. On a table with an unbounded or large result set, it forces the coordinator to hold the full result in memory, increases the chance of timeouts, and can degrade the whole node, not just the one query, because ScyllaDB is shard-per-core and one shard doing this work blocks other work queued on it.

### Why It's Dangerous

- Unbounded memory growth on the coordinator while it assembles the full result
- Increased timeout risk on large tables
- ScyllaDB Cloud enforces a 1 MB hard limit per page; even a high fetch_size does not remove the need for paging, since the driver may return far fewer rows per page than requested if the response would exceed this limit
- Can degrade a whole shard, not just the offending query, due to ScyllaDB's shard-per-core architecture

### Incorrect: Python Driver

```
session.execute("SELECT * FROM events WHERE partition_key = %s", [pk])
# No fetch_size set. The Python driver defaults to 5000 rows per page,
# but if the result set is materially larger, or row size is large,
# this still risks large memory allocation on both client and coordinator.
```

### Correct: Python Driver

```
from cassandra.query import SimpleStatement
statement = SimpleStatement(
    "SELECT * FROM events WHERE partition_key = %s",
    fetch_size=1000
)
for row in session.execute(statement, [pk]):
    process(row)
# The driver transparently fetches subsequent pages as iteration continues.
```

### Incorrect: Rust Driver

```
session.query_unpaged("SELECT * FROM events WHERE partition_key = ?", (pk,)).await?;
// query_unpaged / execute_unpaged bypass paging entirely.
```

### Correct: Rust Driver

```
let mut rows_stream = session
    .query_iter("SELECT * FROM events WHERE partition_key = ?", (pk,))
    .await?;
// query_iter / execute_iter page automatically.
```

### When Skipping Paging Is Acceptable

- Queries guaranteed by the schema to return at most one row (a full primary key lookup)
- A bounded clustering range on a partition that is itself size-bounded by design (see antipattern-large-partitions.md)
- If the result size cannot be bounded by the schema itself, it should be paged rather than left unbounded on the assumption that current data volume is small

### How to Detect

- Grep application code for query_unpaged, execute_unpaged (Rust), or SELECT calls with no fetch_size / page size argument (Python, Java, C#)
- In ScyllaDB Cloud, unusually large per-query response sizes or coordinator memory pressure isolated to specific queries is the operational signal
