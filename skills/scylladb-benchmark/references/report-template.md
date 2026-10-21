---
title: Benchmark report template
tags: report, markdown, results table, reproducibility, cost, timeline, validity
---

# Benchmark report template

Write the report to `scylladb-benchmark-report.md` in the root of the user's project, unless the user gives another path. Fill every field from the API responses and the files in `~/results`. Write "unknown" for a value that you could not get, and say why. Remove the spread table if each step has one run. Copy `~/results` of each loader next to the report, for example to `scylladb-benchmark-results/`.

## Template

```markdown
# ScyllaDB Cloud benchmark: <workload> on <n> × <type>

Date: <UTC date>. Result: <max rate that passed every run, or pass/fail at the target> at p99 ≤ <SLA> ms.
Validity: <valid | invalid: reasons from the validity rules>. Network path: <VPC peering | public network path>.

## Results

| Run | Loaders | Target ops/s | Measured ops/s | p50 ms | p90 ms | p99 ms | Max ms | Errors | Loader CPU | Flags |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| <from cs-row.sh> |

| Step ops/s | Runs | Measured min–max | p99 min–max | p99 spread |
| --- | --- | --- | --- | --- |

Stalls (10 s intervals with p99 above the SLA): <UTC time, length, loader>, or none.
Latency is client-side, from the scheduled start time, merged over all loaders from the HDR logs.
Server-side latency: cluster Monitoring tab, <UTC start>–<UTC end> of each run.

## Environment

| Item | Value |
| --- | --- |
| Cluster | <n> × <type> (<vCPU>, <RAM>), X Cloud, scaling pinned (`instanceTypeIDs` [<id>], `vcpu.min` <n>), <region>, AZ IDs <list> |
| ScyllaDB | <version from the Cloud API> |
| Cluster price | <USD per node-hour> × <n> = <USD/hour> (Cloud API `POST /pricing`, <date>) |
| Loaders | <n> × <type>, one in each AZ ID, rack-aware, <USD/hour> each (<source>) |
| Network | VPC peering, loader CIDR <cidr>, cluster CIDR <cidr> |
| Tool | scylladb/cassandra-stress:4.0.0, ScyllaDB Java driver 3.11.5.20, prepared statements, token-aware, shard-aware |

## Workload

| Item | Value |
| --- | --- |
| Profile | <generic keyspace1.standard1 | profile file>, built from <app files>. Differences from the app: <list> |
| Operations | <ratio>, `cl=LOCAL_QUORUM` |
| Keys | <-pop distribution> over <rows> rows |
| Data size | about <GB> raw per node, RF 3, tablets, <cached | disk> reads |
| Concurrency | <threads> threads on each loader, <rate> ops/s on each loader |
| Timing | warm-up <duration>, <runs> measured runs of <duration> |

## Commands

<The `.cmd` file of each run, and the cs-run.sh connection options: `-node <node IPs> datacenter=<DC> rack=<AZ ID> -mode native cql3 user=scylla password=<hidden> -log interval=10s`>

## Timeline and cost

| Stage | UTC | Minutes from start |
| --- | --- | --- |
| Cluster create request | | 0 |
| Loaders ready | | |
| Cluster ready | | |
| Peering active, ports open | | |
| Populate done | | |
| First run at target within SLA | | |

Cost: <hours> × <USD/hour total> = <USD>, from the create time to the delete time of each resource.

## Cleanup

<Deleted on <date>, or the exact commands to delete each resource.>
```
