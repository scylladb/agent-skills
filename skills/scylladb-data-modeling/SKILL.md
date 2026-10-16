---
name: scylladb-data-modeling
description: ScyllaDB CQL data modeling patterns and anti-patterns, including compaction strategy choice, TTL-based expiration, tombstone management, and lightweight transactions. Use when designing tables, reviewing schemas, migrating from SQL or MongoDB, setting data retention, or troubleshooting performance issues caused by schema problems or deletes, or writing conditional (LWT) statements. Vector indexes go to scylladb-vector-search; DynamoDB API tables go to scylladb-alternator. Triggers on "design schema", "ScyllaDB data model", "partition key", "clustering column", "primary key", "CQL table design", "ALLOW FILTERING", "large partitions", "hot partitions", "query-first design", "secondary index", "materialized view", "schema review", "wide partition", "tombstones", "time series", "BATCH", "paging", "fetch size", "TTL", "default_time_to_live", "compaction strategy", "TWCS", "gc_grace_seconds", "tombstone_gc", "LWT", "lightweight transaction", "IF NOT EXISTS", "LOCAL_SERIAL".
---

# ScyllaDB Data Modeling

If the task goes beyond this skill, use the parent `scylladb` skill for a ScyllaDB overview and the list of other ScyllaDB skills. If it is not installed, fetch it from `https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/scylladb/SKILL.md`.

CQL data modeling patterns and anti-patterns for ScyllaDB. Bad schema is the root cause of most ScyllaDB performance issues — no amount of cluster scaling can fix a fundamentally wrong data model.

## When to Use This Skill

- Designing a new ScyllaDB schema from scratch
- Migrating from SQL/relational databases, MongoDB, or Cassandra to ScyllaDB
- Reviewing existing table designs for performance issues
- Troubleshooting slow queries, timeouts, or hot nodes
- Deciding how to structure primary keys (partition key + clustering columns)
- Modeling time-series, IoT, or event data
- Seeing large partition warnings in logs
- Encountering `ALLOW FILTERING` in queries or code reviews
- Adding secondary indexes or materialized views
- Choosing a compaction strategy, or setting TTLs and retention on a table
- Reads slowed by deletes, expired data, or tombstone warnings
- Writing conditional statements (`IF NOT EXISTS`, `IF EXISTS`, `IF <condition>`) or choosing serial consistency

For adjacent topics, use the sibling skill instead:

- Connecting a driver, choosing a driver, or preparing statements: `scylladb-cloud-setup`
- Vector columns, vector indexes, and ANN queries: `scylladb-vector-search`
- Tables created through the DynamoDB API: `scylladb-alternator`. The partition-key rules in this skill still apply to them.
- Deploying the cluster on Kubernetes, including rack and replication-factor layout: `scylladb-kubernetes`

## Key Principle

> **"Start from the queries, not from the entities."**

This is ScyllaDB's core data modeling philosophy. Unlike relational databases where you normalize entities and then write queries against them, in ScyllaDB you:

1. **List your application's queries** — every `SELECT`, `UPDATE`, and `DELETE` your application will run
2. **Design one table per query pattern** — each table's primary key is crafted to serve a specific query efficiently
3. **Accept denormalization** — the same data may exist in multiple tables, each optimized for a different access pattern

In ScyllaDB, the partition key determines **which node** holds the data and the clustering columns determine **the sort order within** that partition. The primary key IS your access pattern.

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

## Comparison with SQL / MongoDB

| Concept                    | SQL                        | MongoDB                  | ScyllaDB                                                                                                                            |
| -------------------------- | -------------------------- | ------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| Schema design              | Entity-first (normalize)   | Document-first (embed)   | Query-first (denormalize per query)                                                                                                 |
| Data unit                  | Row in a table             | Document in a collection | Row in a partition                                                                                                                  |
| Joins                      | `JOIN` clause              | `$lookup` aggregation    | Not supported — denormalize instead                                                                                                 |
| Aggregates                 | Any column, any `GROUP BY` | Aggregation pipeline     | `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`; `GROUP BY` only on a primary key prefix                                                        |
| Flexible schema            | No (strict DDL)            | Yes (schema-optional)    | No (strict CQL DDL)                                                                                                                 |
| Index required for queries | Often optional             | Recommended              | Partition key required in every query                                                                                               |
| Unique constraint          | `UNIQUE`                   | `unique: true` index     | Primary key only. `INSERT ... IF NOT EXISTS` (LWT) rejects duplicates; for a non-key column, insert into a lookup table keyed on it |
| Transactions               | Full ACID                  | Multi-document ACID      | Lightweight Transactions (LWT) for single-partition linearizable ops                                                                |

## Keyspace creation (ScyllaDB 2025.4 or newer)

As of ScyllaDB 2025.4, `WITH replication` is optional. Use the simple form by default:

```
CREATE KEYSPACE myapp;
```

Explicitly specifying `NetworkTopologyStrategy` and `replication_factor` remains valid but is not required.

Never use `SimpleStrategy`. Tablets support only `NetworkTopologyStrategy`, and many Cassandra tutorials still show `SimpleStrategy`.

New keyspaces use tablets by default (controlled by `tablets_mode_for_new_keyspaces`). Check the ScyllaDB version before using these features in a tablets keyspace:

- **Materialized views and secondary indexes**: supported on tablets as of ScyllaDB 2025.4. The keyspace must stay [RF-rack-valid](https://docs.scylladb.com/manual/stable/architecture/tablets.md) for its whole lifetime.
- **Counters**: supported on tablets as of ScyllaDB 2026.1. On older versions, put counter tables in a vnodes keyspace:

```
CREATE KEYSPACE myapp_counters
  WITH replication = {'class': 'NetworkTopologyStrategy', 'replication_factor': 3}
  AND tablets = {'enabled': false};
```

## Quick Reference

Each reference explains why the rule matters, shows incorrect and correct CQL, and lists when the rule does not apply.

### 1. Anti-Patterns — 5 rules

- [antipattern-allow-filtering](references/antipattern-allow-filtering.md) — `ALLOW FILTERING` forces a full-scan. Consult this reference whenever you see it in a query, or when a query does not include the full partition key.
- [antipattern-large-partitions](references/antipattern-large-partitions.md) — Partitions that grow without bounds cause hot shards, slow reads, and slow repair and streaming. Consult when designing time-series tables or any table where rows accumulate per partition key.
- [antipattern-hot-partitions](references/antipattern-hot-partitions.md) — Uneven partition key distribution causes some nodes/shards to be overloaded while others sit idle. Consult when choosing partition keys for high-write workloads.
- [antipattern-unpaged-queries](references/antipattern-unpaged-queries.md) — Unpaged SELECTs cause unbounded memory growth and cluster instability. Consult when a query may return more rows than a single page, or when reviewing code that calls raw/unpaged execution methods.
- [antipattern-multi-partition-batch](references/antipattern-multi-partition-batch.md) — BATCH statements spanning multiple partitions provide no real atomicity benefit and create coordinator hotspots. Consult when reviewing code that uses BATCH to simulate a transaction, or when migrating SQL transaction logic to CQL.

### 2. Fundamentals — 3 rules

- [query-first-design](references/query-first-design.md) — Design tables from queries, not entities. The methodology for translating application access patterns into CQL table definitions. Consult when starting a new schema or converting a relational or document model into tables.
- [partition-key-design](references/partition-key-design.md) — How to choose partition keys that distribute data evenly and support your queries. Includes composite partition keys. Consult when choosing or reviewing a partition key, or when a single column does not give enough cardinality.
- [clustering-columns](references/clustering-columns.md) — How clustering columns control sort order within a partition, and how to use them for range queries and time-ordered data. Consult when a query needs sorted results, a range condition, or `WITH CLUSTERING ORDER BY`.

### 3. Patterns — 3 rules

- [pattern-bucketing](references/pattern-bucketing.md) — Split unbounded partitions into bounded time buckets (e.g., one partition per day/hour). Essential for time-series and IoT data. Consult when rows accumulate per partition key without a limit.
- [secondary-indexes-and-mv](references/secondary-indexes-and-mv.md) — When to use secondary indexes, local secondary indexes, and materialized views — and when to prefer a denormalized table instead. Consult when a query filters on a column outside the primary key, or before adding `CREATE INDEX` or `CREATE MATERIALIZED VIEW`.
- [lwt](references/lwt.md) — Conditional statements, Paxos cost, serial consistency, atomic arithmetic (ScyllaDB 2026.3+), and differences from Cassandra LWT. Consult when a statement has an `IF` clause, when choosing `SERIAL` or `LOCAL_SERIAL`, when a conditional write times out, or when porting Cassandra LWT code that reads the result set.

### 4. Data Lifecycle — 3 rules

- [compaction-strategies](references/compaction-strategies.md) — Choosing ICS, LCS, or TWCS per workload, the TWCS rules, and safely changing compaction options. Consult when creating a table, when writing a `compaction = {...}` clause, or when disk usage or write amplification is high.
- [ttl](references/ttl.md) — Per-cell TTL semantics, `default_time_to_live`, per-row TTL (ScyllaDB 2026.2+), and how expired data leaves the disk. Consult when data has a retention period, when using `USING TTL`, or when rows expire only partially.
- [tombstones](references/tombstones.md) — What creates tombstones, `tombstone_gc` modes and their defaults, ScyllaDB's empty-page behavior, and the queue anti-pattern. Consult when designing deletes, when reads slow down after deletes, when pages come back empty, or before changing `gc_grace_seconds`.
