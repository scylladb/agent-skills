---
name: scylladb-data-modeling
description: ScyllaDB CQL data modeling patterns and anti-patterns. Use when designing tables, reviewing schemas, migrating from SQL or MongoDB, or troubleshooting performance issues caused by schema problems. Triggers on "design schema", "ScyllaDB data model", "partition key", "clustering column", "primary key", "CQL table design", "ALLOW FILTERING", "large partitions", "hot partitions", "query-first design", "secondary index", "materialized view", "schema review", "wide partition", "tombstones", "time series".
---

# ScyllaDB Data Modeling

CQL data modeling patterns and anti-patterns for ScyllaDB. Bad schema is the root cause of most ScyllaDB performance issues — no amount of cluster scaling can fix a fundamentally wrong data model.

## When to Apply

Reference these guidelines when:
- Designing a new ScyllaDB schema from scratch
- Migrating from SQL/relational databases, MongoDB, or Cassandra to ScyllaDB
- Reviewing existing table designs for performance issues
- Troubleshooting slow queries, timeouts, or hot nodes
- Deciding how to structure primary keys (partition key + clustering columns)
- Modeling time-series, IoT, or event data
- Seeing large partition warnings in logs
- Encountering `ALLOW FILTERING` in queries or code reviews
- Adding secondary indexes or materialized views

## Key Principle

> **"Start from the queries, not from the entities."**

This is ScyllaDB's core data modeling philosophy. Unlike relational databases where you normalize entities and then write queries against them, in ScyllaDB you:

1. **List your application's queries** — every `SELECT`, `UPDATE`, and `DELETE` your application will run
2. **Design one table per query pattern** — each table's primary key is crafted to serve a specific query efficiently
3. **Accept denormalization** — the same data may exist in multiple tables, each optimized for a different access pattern

In ScyllaDB, the partition key determines **which node** holds the data and the clustering columns determine **the sort order within** that partition. The primary key IS your access pattern.

## Quick Reference

### 1. Anti-Patterns — 3 rules

- [antipattern-allow-filtering](references/antipattern-allow-filtering.md) — `ALLOW FILTERING` forces a full-scan. Consult this reference whenever you see it in a query, or when a query does not include the full partition key.
- [antipattern-large-partitions](references/antipattern-large-partitions.md) — Partitions that grow without bounds cause memory pressure, slow reads, and compaction issues. Consult when designing time-series tables or any table where rows accumulate per partition key.
- [antipattern-hot-partitions](references/antipattern-hot-partitions.md) — Uneven partition key distribution causes some nodes/shards to be overloaded while others sit idle. Consult when choosing partition keys for high-write workloads.

### 2. Fundamentals — 3 rules

- [query-first-design](references/query-first-design.md) — Design tables from queries, not entities. The methodology for translating application access patterns into CQL table definitions.
- [partition-key-design](references/partition-key-design.md) — How to choose partition keys that distribute data evenly and support your queries. Includes composite partition keys.
- [clustering-columns](references/clustering-columns.md) — How clustering columns control sort order within a partition, and how to use them for range queries and time-ordered data.

### 3. Patterns — 2 rules

- [pattern-bucketing](references/pattern-bucketing.md) — Split unbounded partitions into bounded time buckets (e.g., one partition per day/hour). Essential for time-series and IoT data.
- [secondary-indexes-and-mv](references/secondary-indexes-and-mv.md) — When to use secondary indexes, local secondary indexes, and materialized views — and when to prefer a denormalized table instead.

## Primary Key Structure

```
PRIMARY KEY ((partition_key_col1, partition_key_col2), clustering_col1, clustering_col2)
            |___________________________________|   |__________________________________|
                     Partition key                         Clustering columns
                 (determines node/shard)             (determines sort order within
                                                      the partition)
```

### Rules

1. **The partition key MUST appear in every `WHERE` clause** — queries that don't specify the full partition key require `ALLOW FILTERING` (a full-scan) or a secondary index
2. **Clustering columns define sort order** — `ASC` by default, configurable with `WITH CLUSTERING ORDER BY`
3. **Partition key determines data distribution** — all rows with the same partition key live on the same node/shard

## How to Use

Each reference file listed above contains detailed explanations and CQL examples. Use the descriptions in the Quick Reference to identify which files are relevant to your current task.

Each reference file contains:
- Brief explanation of why it matters
- Incorrect CQL example with explanation
- Correct CQL example with explanation
- "When NOT to use" exceptions
- Performance impact

## Comparison with SQL / MongoDB

| Concept | SQL | MongoDB | ScyllaDB |
|---------|-----|---------|----------|
| Schema design | Entity-first (normalize) | Document-first (embed) | Query-first (denormalize per query) |
| Data unit | Row in a table | Document in a collection | Row in a partition |
| Joins | `JOIN` clause | `$lookup` aggregation | Not supported — denormalize instead |
| Flexible schema | No (strict DDL) | Yes (schema-optional) | No (strict CQL DDL) |
| Index required for queries | Often optional | Recommended | Partition key required in every query |
| Unique constraint | `UNIQUE` | `unique: true` index | Primary key only |
| Transactions | Full ACID | Multi-document ACID | Lightweight Transactions (LWT) for single-partition linearizable ops |
