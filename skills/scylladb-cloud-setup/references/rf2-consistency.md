---
title: Consistency Levels with Replication Factor 2
impact: HIGH
impactDescription: With RF=2, LOCAL_QUORUM needs both replicas, so one node down makes every LOCAL_QUORUM request fail
tags: consistency, replication-factor, RF=2, LOCAL_ONE, LOCAL_QUORUM, retry-policy, downgrading-consistency, hinted-handoff, repair
---

# Consistency Levels with Replication Factor 2

With RF=2, `LOCAL_QUORUM` needs both replicas (`floor(2/2) + 1 = 2`). When one replica is down, every `LOCAL_QUORUM` request fails with `Unavailable`. Planned downtime counts too: rolling upgrades, restarts, and maintenance. See [consistency levels](https://docs.scylladb.com/manual/stable/cql/consistency.md).

SKILL.md Step 4 sets `LOCAL_QUORUM` as the default. When the keyspace has RF=2 in the local DC, use this file instead.

## Choose a client configuration

| Configuration | Writes | Reads | All replicas up | One replica down |
| --- | --- | --- | --- | --- |
| Semi-consistent (recommended) | `LOCAL_QUORUM` + downgrading retry policy | `LOCAL_ONE` | Consistent: W + R = 3 > RF | Writes go to one replica. Reads can be stale after the node returns |
| Eventually consistent | `LOCAL_ONE` | `LOCAL_ONE` | Reads can be stale | Available. Reads can be stale |
| Full quorum (do not use) | `LOCAL_QUORUM` | `LOCAL_QUORUM` | Consistent | Reads and writes fail |

- Recommend the semi-consistent configuration by default. It is consistent on most days and loses consistency only while a replica is down and until it catches up.
- Use the eventually consistent configuration only when the user accepts stale reads at all times, for example a cache.
- Do not use `LOCAL_QUORUM` reads with RF=2. Users pick RF=2 for fast reads, and full quorum fails when one node is down. If the user needs consistency while a node is down, use RF=3.

## Downgrading retry policy

The policy retries a failed request once, at a lower consistency level, when fewer replicas answer than required. The rules below are for Python, Java 4.x, Rust, C++, and C#. Go differs (see the driver table).

| Error | Policy action |
| --- | --- |
| `Unavailable` (replica known down) | Retry at `ONE` if one replica is alive |
| Read timeout, fewer responses than required | Retry at `ONE` if one replica answered |
| Write timeout, `SIMPLE` or logged `BATCH`, at least one ack | Return success to the application. Do not retry |
| Write timeout, `UNLOGGED_BATCH`, at least one ack | Retry at `ONE` |
| Write timeout, zero acks | Return the error |
| `CAS` (LWT) write timeout | Return the error |

| Driver | Enable | Notes |
| --- | --- | --- |
| Python | `ExecutionProfile(retry_policy=DowngradingConsistencyRetryPolicy())` | Deprecated, raises `DeprecationWarning`. No idempotency check |
| Java 4.x | `datastax-java-driver.advanced.retry-policy.class = ConsistencyDowngradingRetryPolicy` (4.10.0.0+) | Retries a write timeout only for idempotent statements |
| Go | `cluster.RetryPolicy = &gocql.DowngradingConsistencyRetryPolicy{ConsistencyLevelsToTry: []gocql.Consistency{gocql.LocalOne}}` | Retries at the next level in the list, so `LocalOne` is possible. A write timeout with acks returns the error to the application. Never downgrades LWT (v1.18.3+) |
| Rust | `ExecutionProfile::builder().retry_policy(Arc::new(DowngradingConsistencyRetryPolicy::new()))` from `scylla::policies::retry` | Retries a write timeout only for idempotent statements. See [Rust driver docs](https://rust-driver.docs.scylladb.com/stable/retry-policy/downgrading-consistency.md) |
| C++ | `cass_retry_policy_downgrading_consistency_new()` | Deprecated. Wraps the Rust policy |
| C# | `Cluster.Builder().WithRetryPolicy(DowngradingConsistencyRetryPolicy.Instance)` | Obsolete. Returns success for every `SIMPLE`, `BATCH`, or `COUNTER` write timeout, also with zero acks |
| Node.js | Not available | `@scylladb/driver` supports no custom retry policy. Catch `Unavailable` in the application and run the write again at `LOCAL_ONE` |

Python example (`scylla-driver`). Writes use the downgrading policy, reads use `LOCAL_ONE`:

```python
from cassandra import ConsistencyLevel
from cassandra.auth import PlainTextAuthProvider
from cassandra.cluster import Cluster, ExecutionProfile, EXEC_PROFILE_DEFAULT
from cassandra.policies import (
    DCAwareRoundRobinPolicy,
    DowngradingConsistencyRetryPolicy,
    TokenAwarePolicy,
)

lb = TokenAwarePolicy(DCAwareRoundRobinPolicy(local_dc='AWS_US_EAST_1'))

writes = ExecutionProfile(
    load_balancing_policy=lb,
    consistency_level=ConsistencyLevel.LOCAL_QUORUM,
    retry_policy=DowngradingConsistencyRetryPolicy(),
)
reads = ExecutionProfile(
    load_balancing_policy=lb,
    consistency_level=ConsistencyLevel.LOCAL_ONE,
)

cluster = Cluster(
    contact_points=['node-0.your-cluster.cloud.scylladb.com'],
    auth_provider=PlainTextAuthProvider(username='scylla', password='YOUR_PASSWORD'),
    execution_profiles={EXEC_PROFILE_DEFAULT: writes, 'reads': reads},
)
session = cluster.connect()

session.execute("UPDATE myapp.kv SET v = 'v2' WHERE k = 1")
row = session.execute("SELECT v FROM myapp.kv WHERE k = 1", execution_profile='reads').one()
```

Rules:

- Except in Go, the downgraded level is `ONE`, not `LOCAL_ONE`. In a multi-DC cluster, a replica in a remote DC can satisfy it.
- Mark statements idempotent when they are safe to apply twice. Java and Rust do not retry a write timeout for other statements.
- Do not put non-idempotent statements, such as counter updates or list appends, in an unlogged batch with this policy. Python, Go, and C# can apply them twice.
- The policy does not downgrade LWT. For LWT, see the `scylladb-data-modeling` skill.
- Log each downgrade, for example in a subclass of the policy. A downgraded write exists on one replica only, until hints or repair copy it.

## After a node returns

A downgraded write is on one replica. Until the second replica gets it, a `LOCAL_ONE` read routed to the returning node returns the old value. If the only replica with the write fails in this period, the write is lost.

At least one of these mechanisms must copy the write:

- **Hinted handoff.** On by default. The coordinator stores a hint for the down replica and replays it when the replica returns. Hints stop for a node that is down longer than `max_hint_window_in_ms` (default 3 hours). See [hinted handoff](https://docs.scylladb.com/manual/stable/architecture/anti-entropy/hinted-handoff.md).
- **Repair.** Run a repair after the node returns if the outage was longer than the hint window, or if hints are disabled. See [repair](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/maintenance/repair.md).
- **Read repair.** A `LOCAL_ONE` read contacts one replica, so it cannot find a mismatch and does not repair. Only reads at a higher consistency level can repair. See [read repair](https://docs.scylladb.com/manual/stable/architecture/anti-entropy/read-repair.md).

Rolling upgrades and restarts: before you take the next node down, make sure the hints to the previous node are replayed. Otherwise, the next node you stop can hold the only copy of recent writes. To wait for hint replay, use the sync point HTTP API in [hinted handoff](https://docs.scylladb.com/manual/stable/architecture/anti-entropy/hinted-handoff.md).

## Tablets and RF=2

New keyspaces use tablets. A tablets keyspace with a numeric RF of 2 in a DC with 3 racks is not [RF-rack-valid](https://docs.scylladb.com/manual/stable/reference/glossary.md#term-RF-rack-valid-keyspace). Materialized views and secondary indexes in a tablets keyspace need an RF-rack-valid keyspace. Use a [rack list](https://docs.scylladb.com/manual/stable/cql/ddl.md#rack-list-rf) to place the two replicas:

```cql
CREATE KEYSPACE myapp
  WITH replication = {'class': 'NetworkTopologyStrategy', 'AWS_US_EAST_1': ['<rack-1>', '<rack-2>']};
```
