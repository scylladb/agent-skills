---
title: Anti-Pattern: Multi-Partition BATCH
impact: HIGH
impactDescription: Multi-partition batches provide no real atomicity benefit and create coordinator hotspots by defeating shard-aware routing
tags: data-modeling, antipattern, batch, atomicity, coordinator, shard-aware-routing
---

## Anti-Pattern: Multi-Partition BATCH

CQL's BATCH statement is often reached for by anyone translating SQL transaction logic, or by an AI agent doing the same. It is not a transaction. A BATCH spanning multiple partitions is explicitly called out as bad practice by ScyllaDB's own engineering team: it does not provide atomicity guarantees the way a SQL transaction does, and it reduces performance, because the request is sent to a coordinator node that is not necessarily the correct replica or shard for any of the partitions involved. This defeats the shard-aware, token-aware routing that the ScyllaDB drivers are built around.

### Why It's Dangerous

- **No real atomicity across partitions.** A LOGGED batch guarantees all statements will eventually apply, or none will, but "isolated" behavior only holds within a single partition. Across partitions, other clients can observe a partially-applied batch mid-flight.
- **Coordinator hotspot.** The coordinator that receives a multi-partition batch cannot route each statement directly to its owning shard the way a single-partition prepared statement can. It becomes a routing bottleneck for the whole batch.
- **Batchlog overhead.** LOGGED batches (the default) write to a batchlog first to guarantee eventual completion. This is a real write amplification cost, paid on every batch, to buy a guarantee that most multi-partition use cases don't actually need.
- **UNLOGGED does not fix this.** Skipping the batchlog with UNLOGGED removes the atomicity guarantee across partitions entirely; a failure partway through can leave the batch partially applied with no record of it.
- **A hard size limit exists.** ScyllaDB will fail a multi-partition batch outright if it exceeds `batch_size_fail_threshold_in_kb` (a server-side config parameter). A batch built by a loop over many rows, the kind an AI agent generating a "bulk insert" is likely to produce, can hit this ceiling without warning.

### Incorrect

```
-- WRONG: unrelated partitions batched together as if this were a SQL transaction
BEGIN BATCH
  INSERT INTO users (user_id, name) VALUES (11111111-1111-1111-1111-111111111111, 'Alice');
  INSERT INTO orders (order_id, user_id, total) VALUES (22222222-2222-2222-2222-222222222222, 11111111-1111-1111-1111-111111111111, 49.99);
  UPDATE inventory SET stock = stock - 1 WHERE product_id = 33333333-3333-3333-3333-333333333333;
APPLY BATCH;
-- Three different partition keys across three tables. No meaningful atomicity
-- is gained here; this only adds batchlog overhead and coordinator load.
```

### Correct: Application-Level Coordination

```
-- RIGHT: issue each write as its own statement (ideally prepared and
-- async), and handle partial failure in application logic rather than
-- relying on BATCH to fake a transaction
insert_user = session.prepare("INSERT INTO users (user_id, name) VALUES (?, ?)")
insert_order = session.prepare("INSERT INTO orders (order_id, user_id, total) VALUES (?, ?, ?)")
update_stock = session.prepare("UPDATE inventory SET stock = stock - 1 WHERE product_id = ?")

session.execute(insert_user, [user_id, name])
session.execute(insert_order, [order_id, user_id, total])
session.execute(update_stock, [product_id])
# Each statement routes independently to its correct shard.
# If partial failure matters for this workflow, handle retries/compensation
# explicitly in application code rather than expecting BATCH to provide it.
```

### Correct: Single-Partition BATCH

```
-- RIGHT: all statements share the same partition key, so this batch is
-- both atomic and isolated, and routes to a single shard
BEGIN BATCH
  INSERT INTO sensor_readings (sensor_id, day, reading_time, value)
    VALUES ('temp-01', '2026-07-15', '2026-07-15T10:00:00Z', 21.4);
  INSERT INTO sensor_readings (sensor_id, day, reading_time, value)
    VALUES ('temp-01', '2026-07-15', '2026-07-15T10:00:01Z', 21.5);
APPLY BATCH;
-- Same partition key (sensor_id, day) throughout. This is the case BATCH
-- was designed for: grouping several rows into the same partition to save
-- round trips, not simulating a cross-table transaction.
```

### When BATCH Is Appropriate

- All statements in the batch share the same partition key (this is the primary intended use case)
- Reducing round trips for several writes to one partition, where the small overhead of UNLOGGED batching is an acceptable trade for fewer network round trips
- Writing the same logical data into two tables that happen to share the same partition key (a denormalization pattern), not two tables with unrelated keys

### How to Detect

- Grep application code and migration scripts for `BEGIN BATCH` / `APPLY BATCH` and check whether every statement inside shares the same partition key
- Watch for batches built inside a loop over a collection of unrelated entities, a common AI-generated "bulk write" pattern that silently becomes multi-partition
- ScyllaDB logs a warning when a batch exceeds `batch_size_warn_threshold_in_kb`, and rejects it outright above `batch_size_fail_threshold_in_kb`; either showing up in logs is a signal to review the batching logic
