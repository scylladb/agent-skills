---
title: Compaction, TTL and Tombstones
impact: HIGH
impactDescription: "Choosing the compaction strategy and tombstone settings that fit the workload; wrong choices show up as space amplification, read latency or disk-full incidents"
tags: compaction, ics, incremental-compaction, twcs, time-window, lcs, space-amplification-goal, ttl, tombstones, tombstone-gc, gc-grace-seconds
---

## Compaction, TTL and Tombstones

ScyllaDB's compaction controller sets compaction priority from backlog automatically; do not tune compaction throughput by hand. What you do choose is the strategy per table.

### Choose the strategy

| Workload | Strategy | Why |
|---|---|---|
| General, update-heavy, mixed read/write (default choice) | `IncrementalCompactionStrategy` (ICS) | Size-tiered efficiency with near-zero temporary space; safe at 90% disk utilization |
| Time series, logs, anything expiring by TTL | `TimeWindowCompactionStrategy` (TWCS) | Whole SSTables expire and are dropped at once; no tombstone scans |
| Read-mostly with few updates and strict read latency | `LeveledCompactionStrategy` (LCS) | Fewest SSTables per read; higher write amplification |

```sql
ALTER TABLE app.orders WITH compaction = {'class': 'IncrementalCompactionStrategy', 'space_amplification_goal': 1.25};

CREATE TABLE app.metrics (...) WITH default_time_to_live = 2592000
  AND compaction = {'class': 'TimeWindowCompactionStrategy', 'compaction_window_unit': 'DAYS', 'compaction_window_size': 1};
```

- ICS splits each SSTable into fixed-size fragments and releases input fragments as it goes, so temporary space is two fragments rather than twice the data. `space_amplification_goal` bounds the size ratio between the largest tier and the next (1.25–1.5 is typical) at the cost of a little write amplification.
- With TWCS, never update or delete old rows and never write far-out-of-order timestamps; both defeat window expiry.

### TTL

```sql
INSERT INTO app.sessions (...) VALUES (...) USING TTL 3600;
ALTER TABLE app.sessions WITH default_time_to_live = 3600;
```

Expired rows become tombstones until compaction removes them; with TWCS whole files are dropped instead. Vector indexes do not support TTL (see `scylladb-vector-search`).

### Tombstones

- Deletes and TTL expirations write tombstones; many tombstones in one partition slow reads (ScyllaDB warns in the log).
- Prefer repair-based tombstone GC so tombstones are collected as soon as repair proves every replica has seen them, instead of after a fixed `gc_grace_seconds`:

```sql
ALTER TABLE app.orders WITH tombstone_gc = {'mode': 'repair'};
```

- Queue-like patterns (insert, read, delete the head) accumulate tombstones; use TTL + TWCS, bucket by time, or a message system instead.

Docs: https://docs.scylladb.com/manual/stable/architecture/compaction/compaction-strategies.html, https://docs.scylladb.com/manual/stable/cql/ddl.html (tombstone_gc)
