---
title: Lightweight Transactions (LWT)
impact: HIGH
impactDescription: LWT adds Paxos rounds to every write, and mixed LWT and plain writes, wrong serial consistency, or Cassandra assumptions about result sets give wrong results
tags: data-modeling, lwt, lightweight-transactions, paxos, serial-consistency, conditional-update, compare-and-set
---

## Lightweight Transactions (LWT)

An `INSERT`, `UPDATE`, `DELETE`, or `BATCH` with an `IF` clause runs as an LWT: a Paxos round on one partition that gives linearizable compare-and-set. For syntax and semantics, see [Lightweight Transactions](https://docs.scylladb.com/manual/stable/features/lwt.md). This file covers the cost, the mistakes that cause production problems, and the [differences from Cassandra](https://docs.scylladb.com/manual/stable/kb/lwt-differences.md).

```
CREATE TABLE myapp.accounts (account_id uuid PRIMARY KEY, owner text, balance bigint, version int);

INSERT INTO myapp.accounts (account_id, owner, balance, version)
VALUES (11111111-1111-1111-1111-111111111111, 'alice', 100, 1) IF NOT EXISTS;

UPDATE myapp.accounts SET balance = 90, version = 2
WHERE account_id = 11111111-1111-1111-1111-111111111111 IF version = 1;

DELETE FROM myapp.accounts
WHERE account_id = 11111111-1111-1111-1111-111111111111 IF EXISTS;
```

- Restrict the full primary key. If the statement restricts only the partition key, `IF` can test only static columns. `IF` never uses a secondary index.
- Join conditions with `AND` only.
- `IF col = NULL` is true for a missing row too. Use `IF EXISTS` when the row must exist.

### Cost

- Each LWT runs Paxos Prepare, Accept, and Learn rounds to the replicas before it answers. ScyllaDB returns the current row with the Prepare response. Cassandra sends a separate read round ([Paxos in ScyllaDB](https://docs.scylladb.com/manual/stable/features/lwt.md)).
- ScyllaDB writes LWT data to the commit log synchronously, in every `commitlog_sync` mode.
- Concurrent LWTs on the same partition contend: a replica refuses an older ballot and the coordinator retries. Do not put LWT on a hot partition. Use LWT only for data that needs compare-and-set.
- Use prepared statements for LWT and use a ScyllaDB driver (see the `scylladb-cloud-setup` skill). The shard-aware driver sends the request to the correct shard. Drivers that support the [LWT metadata mark](https://github.com/scylladb/scylladb/blob/master/docs/dev/protocol-extensions.md#lwt-prepared-statements-metadata-mark) send contending LWTs to the primary replica first, so they queue instead of compete.
- Tablets: LWT works in tablets keyspaces as of ScyllaDB 2025.4. On older versions, put LWT tables in a keyspace with `tablets = {'enabled': false}`. The first LWT on a tablets table creates its `<table>$paxos` state table, which can cause a one-time latency spike.

### Serial consistency

Each LWT uses two consistency levels: the serial consistency level for Prepare and Accept, and the regular consistency level for Learn ([consistency levels](https://docs.scylladb.com/manual/stable/cql/consistency.md)).

- Use `LOCAL_SERIAL` when one datacenter writes a given key. Use `SERIAL` when more than one datacenter can write the same key at the same time. `LOCAL_SERIAL` is linearizable only within the local datacenter.
- A `QUORUM` read can miss an LWT that is in progress. To read the latest value, including an LWT in progress, read one partition with `SERIAL` or `LOCAL_SERIAL` as the consistency level.

```python
from cassandra import ConsistencyLevel

cas = session.prepare(
    "UPDATE myapp.accounts SET balance = ?, version = ? WHERE account_id = ? IF version = ?")
cas.consistency_level = ConsistencyLevel.LOCAL_QUORUM          # Learn
cas.serial_consistency_level = ConsistencyLevel.LOCAL_SERIAL   # Prepare and Accept

result = session.execute(cas, [90, 2, account_id, 1])
if not result.was_applied:
    current = result.one()  # old row: reload and retry with current.version
```

### Incorrect: mixing LWT and plain writes on the same data

```
-- WRONG: a plain write to a row that other clients change with LWT
UPDATE myapp.accounts SET balance = 0
WHERE account_id = 11111111-1111-1111-1111-111111111111;
-- The plain write skips Paxos, so ScyllaDB cannot keep the
-- conditional statements on this row consistent.
```

### Correct: every write to that data is conditional

```
UPDATE myapp.accounts SET balance = 0
WHERE account_id = 11111111-1111-1111-1111-111111111111 IF EXISTS;
```

See the [LWT limitations](https://docs.scylladb.com/manual/stable/features/lwt.md). Data that no client changes with LWT can use plain writes.

### Atomic arithmetic: use `SET col = col + n` with `IF` (ScyllaDB 2026.3+)

LWT does not work on counter tables (`Conditional updates are not supported on counter tables`). As of ScyllaDB 2026.3, a conditional `UPDATE` can add to or subtract from a regular numeric column. Cassandra rejects this syntax.

```
-- WRONG (all versions): arithmetic on a non-counter column without IF is rejected
UPDATE myapp.accounts SET balance = balance - 10
WHERE account_id = 11111111-1111-1111-1111-111111111111;

-- RIGHT (2026.3+): atomic decrement, applied only if the balance is high enough
UPDATE myapp.accounts SET balance = balance - 10
WHERE account_id = 11111111-1111-1111-1111-111111111111 IF balance >= 10;
```

If the column is null, the result is null. Before 2026.3, read the value and write it back with `IF balance = <old value>`, and retry when `[applied]` is false.

### Result sets and errors

- ScyllaDB always returns `[applied]` and the old values of the primary key and condition columns (all columns for `IF EXISTS` and `IF NOT EXISTS`), also when the statement applies. A new row gives null values. Cassandra returns only `[applied]` on success. Check the `[applied]` column (`was_applied` in Python, `wasApplied()` in Java). Do not infer the result from the column count.
- A conditional batch returns one row per conditional statement, in statement order. Cassandra returns them in clustering key order.
- A write timeout does not mean the LWT failed. The write can be committed. Read the row back with `SERIAL` or `LOCAL_SERIAL`, or retry the same conditional statement and check the old values. An `Unavailable` error with consistency `SERIAL` or `LOCAL_SERIAL` means the statement had no effect. See [error handling](https://docs.scylladb.com/manual/stable/features/lwt.md).

### Conditional batches

- A conditional batch must stay in one partition (see [antipattern-multi-partition-batch.md](antipattern-multi-partition-batch.md)). ScyllaDB ignores `UNLOGGED` on a conditional batch.
- ScyllaDB accepts `IF EXISTS`, `IF NOT EXISTS`, and column conditions for the same row in one batch. Cassandra rejects this. A batch with conditions that cannot all be true does not fail: it returns `[applied] = False`.
