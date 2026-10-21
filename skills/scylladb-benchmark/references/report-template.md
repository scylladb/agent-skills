---
title: Benchmark report template
tags: report, markdown, results table, reproducibility, cost, timeline, validity
---

# Benchmark report template

Write the report to `scylladb-benchmark-report.md` in the root of the user's project, unless the user gives another path. Fill every field from the API responses and the files in `~/results`. Write "unknown" for a value that you could not get, and say why. Copy `~/results` of each loader next to the report, for example to `scylladb-benchmark-results/`.

Contents: [template](#template), [measured run](#measured-run).

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

## Measured run

The default recipe in SKILL.md comes from this run. Use it as an example of a filled report, and as the expected result of the recipe.

- Date: 2026-10-20, us-east-1, AZ IDs use1-az1, use1-az2, use1-az4.
- Cluster: X Cloud, 3 × i4i.2xlarge (8 vCPU, 64 GiB), ScyllaDB 2026.3.3, scaling pinned (`instanceTypeIDs` [64], `vcpu.min` 24). The cluster had 3 × i4i.2xlarge until the end. 4.50524 USD per node-hour (`POST /pricing`).
- Loaders: 3 × c7i.8xlarge, one in each AZ ID, rack-aware, 1.428 USD/hour each (AWS price list). Total with the cluster: 17.80 USD/hour.
- Data: 20,000,000 rows, about 3.6 GB raw per node at RF 3, cached reads. Populate: 3 × 300 threads, 0 errors.
- Workload: `mixed ratio(write=1,read=1) cl=LOCAL_QUORUM -pop dist=uniform(1..20000000)`. 1 min warm-up before each step.

| Run | Loaders | Target ops/s | Measured ops/s | p50 ms | p90 ms | p99 ms | Max ms | Errors | Loader CPU | Flags |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| m150000-1 | 3 | 150000 | 149782 | 0.891 | 2.607 | 3.226 | 41.943 | 0 | 11% | valid |
| m150000-2 | 3 | 150000 | 149491 | 0.910 | 2.564 | 3.228 | 177.340 | 0 | 10% | valid |
| m200000-1 | 3 | 200000 | 199802 | 1.820 | 3.082 | 288.883 | 778.043 | 0 | 14% | valid |
| m200000-2 | 3 | 200000 | 199565 | 1.738 | 2.898 | 4.227 | 317.194 | 0 | 15% | valid |
| r200000-1 | 3 | 200000 | 199880 | 1.744 | 2.808 | 3.879 | 53.248 | 0 | 14% | valid |
| r200000-2 | 3 | 200000 | 199597 | 1.764 | 2.931 | 4.061 | 64.225 | 0 | 14% | valid |
| r240000-1 | 3 | 240000 | 239548 | 2.568 | 4.674 | 413.925 | 598.737 | 0 | 18% | valid |
| r240000-2 | 3 | 240000 | 238928 | 2.437 | 3.482 | 142.606 | 349.438 | 0 | 16% | valid |
| s220000-1 | 3 | 220000 | 219277 | 2.090 | 3.090 | 4.563 | 121.569 | 0 | 17% | valid |
| s220000-2 | 3 | 220000 | 219591 | 2.085 | 3.101 | 4.518 | 82.969 | 0 | 14% | valid |
| u230000-1 | 3 | 230000 | 229004 | 2.288 | 3.170 | 5.091 | 681.050 | 0 | 25% | valid |

The runs are in time order. Threads on each loader: 300 at 150,000, 400 for all other runs.

- 220,000 is the recipe target: it passed every run. 230,000 passed its only run.
- 240,000 failed both runs. All loaders had stalls at the same time, up to 556 ms in a 10 s interval. The cause is on the server side.
- m200000-1 had stalls in its first 50 s, 10 min after populate. The next 3 runs at 200,000 passed. A run soon after populate can fail on stalls, so the workflow repeats a failed run once.
- The Cloud MCP tool `monitor_cluster` showed a cluster CPU load of up to 96.9% during the steps.

| Stage | UTC | Minutes from start |
| --- | --- | --- |
| Cluster create request | 15:54:34 | 0 |
| Loaders running | 15:55 | 1 |
| Cluster ready | 16:01:40 | 7 |
| Peering active, ports open | 16:02:58 | 8 |
| Populate done | 16:04:42 | 10 |
| First run at a target within SLA (m150000-1) | 16:11:00 | 16 |
