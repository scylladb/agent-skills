---
name: scylladb-benchmark
description: Run a repeatable load test of a ScyllaDB Cloud cluster on AWS with ScyllaDB's cassandra-stress, from loader VMs that connect through VPC peering, and write a report with a fixed results table. The default fast path measures the maximum 50/50 read/write rate at p99 ≤ 10 ms on a pinned X Cloud cluster with a measured recipe; a user profile tests the schema and queries of the user's application. Use this skill when a user asks to benchmark, load test, or stress test ScyllaDB Cloud, to measure p50, p90, and p99 latency at a target rate, to find the maximum throughput under a latency SLA, or to check if a cluster size is enough. Connecting an application to a cluster goes to scylladb-cloud-setup, and schema design goes to scylladb-data-modeling. Triggers on "benchmark ScyllaDB", "load test my cluster", "stress test", "cassandra-stress", "user profile", "ops/s", "max throughput", "p99 latency", "latency SLA", "read/write ratio", "loader", "benchmark report".
---

# ScyllaDB Cloud Benchmark

If the task goes beyond this skill, use the parent `scylladb` skill for a ScyllaDB overview and the list of other ScyllaDB skills. If it is not installed, fetch it from `https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/scylladb/SKILL.md`.

This skill creates a private ScyllaDB Cloud cluster and AWS loader VMs in a peered VPC, runs `scylladb/cassandra-stress` at fixed rates, and writes a report that another engineer can repeat. The most important rule: set a fixed rate with `-rate threads=T fixed=N/s`. A run without a fixed rate hides queueing delay ([On Coordinated Omission](https://www.scylladb.com/2021/04/22/on-coordinated-omission/)).

## When to Use This Skill

- The user asks to benchmark or load test ScyllaDB Cloud, with or without the queries of their app
- The user asks for p50, p90, or p99 latency at a rate or a read/write ratio
- The user asks for the maximum rate under a latency SLA, or if a cluster size is enough

For adjacent topics, use the sibling skill instead:

- Driver settings and connection code for the application itself: `scylladb-cloud-setup`
- Schema review before you build the workload profile: `scylladb-data-modeling`
- Cluster management through the Cloud MCP server: `scylladb-cloud-mcp`

## Default recipe (fast path)

Use this recipe when the user gives no other shape or workload. It was measured on 2026-10-20 with ScyllaDB 2026.3.3 and `scylladb/cassandra-stress:4.0.0` in us-east-1 ([measured run](references/report-template.md#measured-run)).

| Item | Value |
| --- | --- |
| Cluster | X Cloud, 3 × i4i.2xlarge, the largest AWS type with `freeTier: true` in the Cloud API instance list. Scaling pinned. |
| Loaders | 3 × c7i.8xlarge, one in each cluster AZ ID, `rack=<AZ ID>` |
| Data | 20,000,000 rows of the default `standard1` row, split across the loaders |
| Workload | `mixed ratio(write=1,read=1)`, `cl=LOCAL_QUORUM`, `-pop dist=uniform(1..20000000)` |
| Target | 220,000 ops/s in total: `-rate threads=400 fixed=73333/s` on each loader |
| Timing | Populate with 300 threads on each loader, 1 min warm-up, 2 measured runs of 3 min. The first result came 16 min after the cluster create request. |
| SLA | p99 ≤ 10 ms |
| Measured | 220,000 ops/s passed 2 of 2 runs: p99 4.5–4.6 ms, 0 errors, loader CPU ≤ 17%. 230,000 passed 1 of 1 run (p99 5.1 ms). 240,000 failed 2 of 2 runs on stalls. |

## Select the test

| The user asks | Run |
| --- | --- |
| "Benchmark ScyllaDB", "load test", no details | The default recipe |
| "Load test with the queries of this app" | A `user profile=` built from the app ([workload-profile](references/workload-profile.md)), on the default cluster and loaders |
| "Can it do N ops/s at p99 < X ms?" | The default flow at target N |
| Max throughput on another shape | A step search ([cassandra-stress-commands](references/cassandra-stress-commands.md#find-the-maximum-rate-with-a-step-search)) |
| "Is this cluster size enough?" | The production rate and ratio, 30 min or more for each run |

## Questions to ask first

Ask all of these in one message. Give the default with each question.

1. Workload: the default recipe, or the queries of the app in this repository? Default: the recipe. For the app, ask for the read/write ratio and the production data size.
2. SLA. Default: p99 ≤ 10 ms, the SLA of the [i8g benchmark](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/).
3. AWS region and AWS CLI profile. Default: us-east-1, the region of the recipe.
4. Reuse a cluster that has a private connection? Default: no, create a new one.
5. Change other items of the recipe: cluster type or size, loaders, target rate, or the public network path? Default: no change.

The user can change every default. A changed cluster or loader shape has no measured recipe. For it, run a step search.

## Core rules

- **Never run a benchmark on a production cluster or production data.**
- **Show the cost first.** Show the hourly cost of the cluster and the loaders, and the estimate for the test. Get approval before you create anything.
- **Use a private connection.** Create the cluster with `"broadcastType": "PRIVATE"` and connect the loaders through VPC peering. Use the public IP allowlist only if the user asks. Say that it is less secure and adds a network path that is not representative. Mark the report "public network path".
- **Put one loader in each cluster AZ ID** and set `rack=<AZ ID>`. A rack-aware client sends requests to coordinators in its own zone ([network costs](https://www.scylladb.com/2023/11/08/network-costs-with-scylladb/)).
- **Never run the loader on the user's laptop or on a cluster node** ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).
- **Use `scylladb/cassandra-stress:4.0.0`.** It ships the shard-aware ScyllaDB Java driver 3.11.5.20, wraps each load balancing policy in `TokenAwarePolicy`, and uses prepared statements ([source](https://github.com/scylladb/cassandra-stress)).
- **Create the keyspace yourself** with `NetworkTopologyStrategy`, the DC name, and RF 3, and set `cl=LOCAL_QUORUM` ([production readiness](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/production-readiness.md)). The cassandra-stress defaults are RF 1 and `LOCAL_ONE` ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).
- **Keep loader CPU at or below 50%** ([benchmarking tutorial](https://github.com/scylladb/scylladb/wiki/Benchmarking-Tutorial)).
- **Measure each rate at least twice** ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). Merge percentiles. Do not average them.
- **Report no number without evidence** from a `.out`, `.hdr`, or `.vmstat` file in `~/results`.
- **Never print, log, or commit the CQL password or the API token.**
- **Tag every AWS resource** with `scylladb-benchmark=<run-id>`.

## Workflow

1. **Ask the questions.** Get the API token in `SCYLLADB_CLOUD_API_TOKEN` ([create a token](https://cloud.docs.scylladb.com/stable/api-docs/create-api-token.md)). Record the start time.
2. **Show the plan and the cost, and get approval** ([cluster-and-peering](references/cluster-and-peering.md#look-up-ids-and-prices), [loader-vm-aws](references/loader-vm-aws.md#price-and-size)).
3. **Create the cluster and the loaders at the same time.** Send the cluster request with fixed AZ IDs, then create the loader network and VMs in the same AZ IDs ([cluster-and-peering](references/cluster-and-peering.md#create-the-cluster), [loader-vm-aws](references/loader-vm-aws.md#create-the-loader-network)).
4. **Peer the VPCs and prepare the loaders** when the cluster is ready ([cluster-and-peering](references/cluster-and-peering.md#peer-the-loader-vpc), [loader-vm-aws](references/loader-vm-aws.md#prepare-the-loaders)).
5. **Install the helpers, create the keyspace, and populate** from all loaders ([cassandra-stress-commands](references/cassandra-stress-commands.md)).
6. **Warm up, then run at the target twice.** After the first valid run within the SLA, tell the user the rate and the p99 at once. Then finish the second run. If a run fails the SLA, repeat it once. If the repeat also fails, tell the user, and run a step search down from the target ([cassandra-stress-commands](references/cassandra-stress-commands.md#run-at-the-target-rate), [results-and-report](references/results-and-report.md)).
7. **Write `scylladb-benchmark-report.md`** in the user's project with the fixed results table and the repeat data ([report-template](references/report-template.md)).
8. **Ask the user if you can delete the infrastructure**: loaders, peering, VPC and network resources, key pair, and cluster. Delete only after the user says yes. If the user says no, print the exact cleanup commands ([loader-vm-aws](references/loader-vm-aws.md#clean-up), [cluster-and-peering](references/cluster-and-peering.md#delete-the-peering-and-the-cluster)).

## Quick Reference

- [cluster-and-peering](references/cluster-and-peering.md) — Cloud API calls for IDs, free-trial types, prices, a pinned private X Cloud cluster with fixed AZ IDs, credentials, VPC peering, Standard and public options, reuse, and deletion. Consult before you call the Cloud API or when the loaders cannot reach port 9042.
- [loader-vm-aws](references/loader-vm-aws.md) — AWS CLI commands for the tagged loader VPC and one loader in each AZ ID, the `each` helper, loader price, and cleanup. Consult before you create or delete any AWS resource.
- [cassandra-stress-commands](references/cassandra-stress-commands.md) — Run helpers, keyspace, split populate, target runs, interval log, step search, and TLS. Consult before you run cassandra-stress, or when a run fails or prints no results.
- [workload-profile](references/workload-profile.md) — How to turn the app schema and queries into a cassandra-stress YAML user profile, with a verified example. Consult when the user wants the workload of their app.
- [results-and-report](references/results-and-report.md) — Thread count, dataset size, p50/p90/p99 merged from the HDR logs of all loaders, the results row, and the validity rules. Consult when you plan the load and when you read a run.
- [report-template](references/report-template.md) — The Markdown report file and the measured run behind the default recipe. Consult when you write the report.
