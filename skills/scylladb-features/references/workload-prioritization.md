---
title: Workload Prioritization (Service Levels)
impact: HIGH
impactDescription: "Lets OLTP, analytics, batch and multiple tenants share one cluster with per-workload SLAs"
tags: workload-prioritization, service-level, shares, timeout, oltp, olap, batch, multi-tenant, sla
---

## Workload Prioritization

**Problem it solves:** a latency-sensitive workload (OLTP, real-time serving) shares a cluster with batch ETL, analytics, index rebuilds or another tenant, and must keep its latency when the cluster is saturated.

ScyllaDB's userspace CPU and I/O schedulers already isolate background work (compaction, repair, streaming) from queries. Service levels extend the same mechanism to user workloads.

### CQL

```sql
CREATE SERVICE LEVEL oltp  WITH shares = 600 AND timeout = 20ms AND workload_type = 'interactive';
CREATE SERVICE LEVEL batch WITH shares = 100 AND timeout = 20s  AND workload_type = 'batch';

ATTACH SERVICE LEVEL oltp  TO app_role;
ATTACH SERVICE LEVEL batch TO etl_role;

LIST ALL SERVICE LEVELS;
LIST ATTACHED SERVICE LEVEL OF app_role;
ALTER SERVICE LEVEL batch WITH shares = 50;
DETACH SERVICE LEVEL FROM etl_role;
DROP SERVICE LEVEL batch;
```

### Semantics

- `shares` is a relative weight of CPU and I/O. Think in ratios (600:100), not absolutes. Idle shares flow to whoever is running, so a batch job gets the whole machine at night and 1/7 of it during the day.
- `workload_type = 'interactive'` sheds load when the cluster is over capacity: requests beyond capacity fail fast, latency stays bounded, the application retries or degrades.
- `workload_type = 'batch'` throttles: requests are slowed to their share, never dropped.
- `timeout` applies to every statement from the role unless the statement overrides it with `USING TIMEOUT` (see `query-protection.md`). Interactive workloads get short timeouts (tens of ms); batch gets long ones.
- A service level is attached to a role. A user inherits it at login; one connection, one service level. Give each application or tenant its own role.
- ScyllaDB Monitoring shows latency and throughput per service level, which is how to prove the SLA.

### Typical configurations

| Scenario | Service levels |
|---|---|
| OLTP + nightly analytics | `oltp` interactive 600, `analytics` batch 100 |
| Several microservices with different SLOs | one interactive level per SLO tier, shares by priority |
| Multi-tenant SaaS | one level per tier (gold/silver/bronze), one role per tenant |
| AI serving + batch index rebuilds | `serve` interactive, `rebuild` batch; rebuilds never touch the serving tail |
| Migration or backfill into a live cluster | `backfill` batch with low shares and a long timeout |

### Anti-patterns

- One role for everything: no isolation is possible.
- Setting `shares` to express an absolute throughput; it is a weight.
- Using the cluster-wide `request_timeout` to protect OLTP; use a service level or `USING TIMEOUT` so batch can keep a long timeout.

Docs: https://docs.scylladb.com/manual/stable/features/workload-prioritization.html
