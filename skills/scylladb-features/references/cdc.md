---
title: Change Data Capture (CDC)
impact: HIGH
impactDescription: "Streams every change out of a table with no application double-write; the integration point for Kafka, search, caches, lakes and ScyllaDB's own vector index"
tags: cdc, change-data-capture, kafka, debezium, streaming, preimage, postimage, event-sourcing
---

## Change Data Capture

**Problem it solves:** feed Kafka, a search or vector index, a cache, a warehouse or an audit log with every change, without the application writing twice.

### How it works

- CDC is enabled per table. For each base write, the **coordinator writes a log entry in the same request** to the CDC log table `<table>_scylla_cdc_log`. The request count does not change.
- The log is a regular table queried with CQL and ordinary drivers. Each row records the operation, the changed columns, optionally the row before (`preimage`) and after (`postimage`), and a TTL.
- Entries are partitioned into **streams** and ordered per partition key within a stream; consumers scale out by stream. The log expires by TTL (default 24 h).
- ScyllaDB's own vector index is fed by CDC; the same path serves Elasticsearch, Redis caches, data lakes and Debezium.

### CQL

```sql
CREATE TABLE app.orders (...) WITH cdc = {'enabled': true, 'preimage': true, 'postimage': true, 'ttl': 86400};
-- or on an existing table:
ALTER TABLE app.orders WITH cdc = {'enabled': true};

-- The log table (do not poll it by hand in production; use a connector or library):
SELECT * FROM app.orders_scylla_cdc_log WHERE "cdc$stream_id" = ? AND "cdc$time" > ?;
```

### Consuming

| Consumer | Use |
|---|---|
| ScyllaDB Kafka source connector (Kafka Connect) | Kafka topics per table, at-least-once |
| Debezium ScyllaDB connector | Kafka with Debezium envelope |
| scylla-cdc-java, scylla-cdc-go, scylla-cdc-rust | Custom consumers; handle stream generations and checkpoints for you |
| ScyllaDB Vector Search | Automatic, no setup |

### Rules

- Enable `preimage` only when consumers need the old row; it adds a read before the write.
- Set the log TTL to cover the longest consumer outage you want to survive; the log is stored like any other table.
- `TRUNCATE` on the base table is not propagated to CDC (relevant to vector indexes: drop and recreate instead).
- CDC on tablet keyspaces is supported on current releases; check release notes for older customer versions.
- Write throughput roughly doubles on the storage side (base + log); plan capacity accordingly, and prefer CDC over application double-writes, which are both slower and inconsistent under failure.

Docs: https://docs.scylladb.com/manual/stable/features/cdc/
