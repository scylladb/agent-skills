---
title: Consistency, Lightweight Transactions and Strongly Consistent Tables
impact: HIGH
impactDescription: "Which consistency mechanism to use, what each one costs, and what is roadmap"
tags: consistency, lwt, lightweight-transactions, paxos, raft, strong-consistency, transactions, consistency-level
---

## Consistency

### Default: tunable consistency with LOCAL_QUORUM

- Write and read with `LOCAL_QUORUM` and RF=3 per datacenter: a write is acknowledged by two of three replicas, a read consults two, so a successful read sees every successful write. This is the right default for almost every workload.
- `LOCAL_ONE` reads trade a small window of staleness for lower latency and higher throughput; use for data where last-writer-wins is acceptable.
- Drivers set consistency per statement; set it on the prepared statement or the session default, not in CQL.

### Lightweight transactions (available now)

For compare-and-set, uniqueness and read-your-own-write across clients:

```sql
INSERT INTO app.users (id, email) VALUES (?, ?) IF NOT EXISTS;
UPDATE app.accounts SET balance = ? WHERE id = ? IF balance = ?;
DELETE FROM app.locks WHERE name = ? IF owner = ?;
```

- LWT is Paxos: several round trips per request and retries under contention. Keep it to the operations that need it and keep contended partitions small.
- Use `SERIAL` / `LOCAL_SERIAL` for reads that must observe in-flight LWT writes.
- LWT is single-partition. Multi-partition atomicity is not available today (multi-partition `BATCH` is not atomic across partitions; see `scylladb-data-modeling`).

### Strongly consistent tables (roadmap; position as coming)

Raft-based tables where each tablet is a Raft group: one round on the leader instead of Paxos rounds, no retries under contention, linearizable reads through Raft leases. Planned syntax:

```sql
CREATE TABLE app.ledger (...) WITH consistency = 'strong';
```

Followed by multi-key transactions. Do not state these as available unless the release notes for the customer's version say so.

### Alternator

Alternator maps DynamoDB consistent reads and conditional writes onto CQL consistency and LWT via `alternator_write_isolation`; see skill `scylladb-alternator`.

Docs: https://docs.scylladb.com/manual/stable/features/lwt.html, https://docs.scylladb.com/manual/stable/architecture/raft.html
