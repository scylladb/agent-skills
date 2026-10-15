---
title: Tablets and Raft
impact: CRITICAL
impactDescription: "Changes how clusters scale and how every topology and schema operation behaves; most Cassandra-era operational advice is wrong on ScyllaDB 2025.x+"
tags: tablets, raft, topology, elasticity, scaling, bootstrap, decommission, cleanup, replication
---

## Tablets and Raft

**Raft group 0** is a cluster-wide, linearizable store for topology, tablet placement and schema, replicated on every node with automatic leader election. **A tablet** is a range of a table's tokens (about 5 GB) with its own memtable, SSTables and compaction, placed per (node, shard). Placement is a map held in Raft, not a function of the token ring, so one tablet can move without touching anything else.

Both are on by default in ScyllaDB 2025.1+ and ScyllaDB Cloud. There is nothing to install or enable.

### What changes for an agent's advice

| Cassandra-era advice | ScyllaDB with tablets |
|---|---|
| Add nodes one at a time | Add or remove many nodes at once; a rack scales as one operation |
| A new node serves after streaming completes (hours) | A new node serves as soon as its first tablets land (minutes) |
| Run `nodetool cleanup` after scaling | Not needed; a tablet's SSTables are deleted when it leaves, space returns in seconds |
| Keep 30–50% disk free for compaction and cleanup | 90% disk utilization is safe (ScyllaDB Cloud X Cloud runs there) |
| Use identical instance types | Mix instance types and generations; the load balancer equalizes storage utilization, not tablet count |
| Avoid schema changes while nodes are down | Schema and topology changes are Raft transactions: serialized, resumable, safe while other nodes are down |
| Small tables are split into thousands of vnode pieces | Tablet count is per table; a small table has a few tablets, so scans and index lookups stay fast |

### CQL

```sql
-- Tablets are on by default for new keyspaces. To be explicit:
CREATE KEYSPACE app
  WITH replication = {'class': 'NetworkTopologyStrategy', 'dc1': 3}
  AND tablets = {'enabled': true};

-- Optional: pre-size a table known to be large (tablets also split and merge on their own):
CREATE TABLE app.events (...) WITH tablets = {'min_per_shard': 2};

-- Changing RF or adding a DC is an ALTER; the tablet scheduler rebuilds replicas in the background:
ALTER KEYSPACE app WITH replication = {'class': 'NetworkTopologyStrategy', 'dc1': 3, 'dc2': 3};
```

### Rules

- Use `NetworkTopologyStrategy`; `SimpleStrategy` is not supported with tablets.
- Use a ScyllaDB driver with tablet-aware routing (all current ScyllaDB drivers); older or Cassandra drivers work but lose single-hop routing and will log extra coordinator hops.
- Do not run `nodetool cleanup` after topology changes on tablet keyspaces.
- Feature compatibility on tablet keyspaces has grown release by release (LWT, CDC, materialized views, secondary indexes, counters). Check the release notes for the customer's exact version before recommending a feature on a tablet keyspace; on current releases all of these are supported.
- Keyspaces created before tablets (vnode-based) keep working; migration to tablets is a keyspace-level choice.

### How it works (for explaining to users)

- Every topology request (join, leave, replace, rebuild) is written to `system.topology` in Raft. One elected **topology coordinator** drives it step by step; progress is committed, so it resumes after a leader change.
- The **tablet scheduler** runs on the Raft leader and executes tablet transitions: migration, intra-node migration, rebuild, repair, split and merge. Limits keep nodes healthy (a few migrations in and out per shard at a time).
- Every request is fenced by a topology version: a replica rejects a request planned against an older topology, so no write lands on a stale replica set during a migration.
- Tablet migration copies SSTable files as they are (no row re-serialization), which is why it saturates NVMe and the network.

### Coming on this base (roadmap; do not promise dates)

Incremental repair (only unrepaired data is touched), zero-token/arbiter nodes (`join_ring: false`, Raft quorum without data), recovery after majority loss, strongly consistent tables (see `consistency-and-lwt.md`), Raft leases for single-hop consistent reads, native object-storage tier with NVMe cache.

Docs: https://docs.scylladb.com/manual/stable/architecture/tablets.html, https://docs.scylladb.com/manual/stable/architecture/raft.html
