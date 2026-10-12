---
name: scylladb-features
description: The entry point for using ScyllaDB well. Use this skill whenever a task involves ScyllaDB (or a Cassandra / DynamoDB workload that could run on it) and the question is which feature to use — isolating OLTP from batch or analytics, streaming changes out, scaling or operating a cluster, protecting latency from hot keys or scans, choosing compaction or tombstone settings, needing stronger consistency, or deciding whether a ScyllaDB feature exists for a problem. Trigger on "ScyllaDB", "Scylla", "tablets", "Raft", "workload prioritization", "service level", "CDC", "change data capture", "ICS", "compaction strategy", "tombstone", "rate limit", "BYPASS CACHE", "LWT", "lightweight transaction", "scale out", "add nodes", "disk utilization", "batch job slows OLTP", "stream changes to Kafka", "hot key", "count rows", and on Cassandra or DynamoDB questions where ScyllaDB is the target. Read it before answering from general Cassandra knowledge, because ScyllaDB has features and defaults Cassandra does not. For schema design go to scylladb-data-modeling; for vector search, Alternator, Kubernetes and Cloud connection setup go to those skills.
---

# ScyllaDB features: use the right one for the job

ScyllaDB is a wide-column, CQL- and DynamoDB-compatible database built shard-per-core in C++. Since the 2021–2025 re-architecture, cluster metadata lives in Raft and data lives in tablets, so clusters are elastic, operations are transactional, and many knobs Cassandra users reach for no longer exist. This skill is the discovery map: find the problem in the table, read the reference, apply the feature.

Applies to ScyllaDB 2025.1 and later (one unified, source-available release line; 2026.x at time of writing) and ScyllaDB Cloud (including X Cloud). Where a feature is Cloud-only or roadmap, the reference says so.

## Problem → feature

| You need to | Use | Read |
|---|---|---|
| Scale out in minutes, mix instance sizes, run at 90% disk utilization | Tablets (default for new keyspaces) | `references/tablets-and-raft.md` |
| Safe concurrent schema changes, parallel bootstrap/decommission, resumable topology ops | Raft (on by default; nothing to configure) | `references/tablets-and-raft.md` |
| Keep OLTP latency when batch, analytics or another tenant shares the cluster | Workload prioritization (service levels) | `references/workload-prioritization.md` |
| Stream every change to Kafka, a search or vector index, a cache, a lake | CDC | `references/cdc.md` |
| Compare-and-set, uniqueness, read-your-own-write | Lightweight transactions now; strongly consistent tables (Raft) next | `references/consistency-and-lwt.md` |
| Stop a bot, hot key or retry storm from flooding the cluster | Per-partition rate limit | `references/query-protection.md` |
| Run large scans without evicting the OLTP working set | `BYPASS CACHE` | `references/query-protection.md` |
| Bound latency per statement or per user | `USING TIMEOUT`, service-level timeouts | `references/query-protection.md` |
| Expiring data, time series, logs | TTL + TimeWindowCompactionStrategy | `references/compaction-and-tombstones.md` |
| Update-heavy tables with low space overhead | IncrementalCompactionStrategy + space amplification goal | `references/compaction-and-tombstones.md` |
| Tombstones collected without guessing gc_grace_seconds | `tombstone_gc = {'mode': 'repair'}` | `references/compaction-and-tombstones.md` |
| Count/sum/avg over a table or partition | Distributed aggregates (pushed down automatically) | `references/query-protection.md` |
| See what is happening per shard, table, workload; repair, backup, restore | ScyllaDB Monitoring, ScyllaDB Manager, Cloud | `references/observability-and-ops.md` |
| Query by a non-key column, denormalize | Secondary index (global/local), materialized view | skill `scylladb-data-modeling` |
| Similarity search over embeddings | Vector search | skill `scylladb-vector-search` |
| DynamoDB API | Alternator | skill `scylladb-alternator` |
| Deploy on Kubernetes | ScyllaDB Operator | skill `scylladb-kubernetes` |
| Connect an application, choose a driver | ScyllaDB drivers (shard- and tablet-aware) | skill `scylladb-cloud-setup` |

## Before any feature: the data model

Tablets removed the operational traps; the data-model traps remain. Most "ScyllaDB is slow" questions are a hot or large partition, not a missing feature. Check `scylladb-data-modeling` first when a question involves a schema, then come back here for the feature.

Defaults an agent should assume:

- `LOCAL_QUORUM` for reads and writes, RF=3 per datacenter, `NetworkTopologyStrategy` (required with tablets).
- Prepared statements, driver paging, single-partition batches only, no `ALLOW FILTERING` on large tables.
- Prefer fewer, larger nodes; ScyllaDB scales linearly with cores and disks per node.

## How to answer a ScyllaDB question with this skill

1. Find the problem class in the table above and read that reference.
2. If the question involves a schema, apply `scylladb-data-modeling` first.
3. Give the exact CQL or config, state the edition or version it needs, link the doc page.
4. Say plainly when something is roadmap (strongly consistent tables, multi-key transactions, object storage tier, full-text search, automatic large-partition handling) rather than available.
5. For capacity questions: ScyllaDB Cloud X Cloud runs at 90% storage utilization and scales nodes in parallel; recommend fewer, larger nodes and let the tablet load balancer handle placement.

Further reading: https://docs.scylladb.com/, https://cloud.docs.scylladb.com/, https://university.scylladb.com/
