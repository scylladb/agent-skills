---
title: Advice for a benchmark that compares ScyllaDB with another database
tags: comparison, competitor, fair benchmark, apples to apples, managed service, durability, consistency, open loop, coordinated omission, max throughput under SLA, variance, reproducibility
---

# Advice for a benchmark that compares ScyllaDB with another database

This skill does not create, configure, or run another database. When the user wants a comparison, give the rules in this file. Offer to run the ScyllaDB side with the default flow of this skill. The user runs the other side.

Contents: [client](#client), [resources](#resources), [workload](#workload), [durability and consistency](#durability-and-consistency), [load and metrics](#load-and-metrics), [runs and report](#runs-and-report), [positioning](#positioning).

## Client

- Run the client on separate machines, in the same region and the same AZs as each database. The network round trip changes latency. With a fixed connection count, it also changes throughput.
- Use the same network path for both: private peering on both sides, or the public path on both sides.
- Check that the client is not the bottleneck. CPU and network must stay well below capacity on every loader, for both databases.
- Use the same benchmark tool for both if it supports both ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). If not, use tools with the same load model and the same latency measurement.

## Resources

- Give both databases the same resources: the same hourly cost, or the same vCPU and RAM on the same instance generation. A newer CPU generation alone changes the result.
- Compare a managed service with a managed service: ScyllaDB Cloud against the managed service of the other database. Keep the service defaults on both sides.
- For self-managed databases, align the config options that have the same purpose, and write each change in the report.
- Write the cluster shape of both sides: node count, instance type, storage type, and replication.

## Workload

- Use the same data size relative to RAM on both sides. Say if reads come from cache or from disk. For a sizing decision, use a dataset larger than RAM.
- Use the same key distribution: uniform, or Zipfian with hot keys.
- Use the same read/write ratio and the same row or document size.
- Select workloads that fit the stated purpose of both databases. Do not select a workload that one database was not built for.
- When the user has an application, use its queries on both sides ([workload-profile](workload-profile.md)).

## Durability and consistency

- Use equal durability and consistency on both sides. For ScyllaDB, use RF 3 and `LOCAL_QUORUM`. On the other side, use the matching majority write and read settings.
- A comparison with weaker durability on one side is not valid. Write the settings of both sides in the report.

## Load and metrics

- Use a fixed rate (open loop) on both sides. A closed-loop client waits for each reply, so a stall hides the queued requests (coordinated omission, [benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).
- Report the maximum throughput at a p99 SLA. Do not report the peak closed-loop throughput or the mean latency as the result.
- Measure throughput and p50, p90, p99, and p99.9 if the tool gives it. Do not report only averages.
- Show the 10 s intervals or a time series, so stalls are visible.
- Warm up both databases before you measure.
- Run long enough to include background work. For ScyllaDB, that is compactions. The other database has its own, for example checkpoints or garbage collection. Use the same duration on both sides.

## Runs and report

- Run each step at least twice on each side. Report the spread (min–max), not one percentage difference.
- Write everything that another engineer needs to repeat the test: instance types, versions, configs, the tool, the exact command lines, and the network path.
- If two results differ, give a hypothesis for the cause: hardware, config, workload shape, cache, or network.
- Keep the ScyllaDB side on the setup of this skill: private network, rack-aware loaders, RF 3, `LOCAL_QUORUM`, and a fixed rate. Otherwise the ScyllaDB number is not valid.

## Positioning

- Keep the tone technical. Do not attack the other database. Say where it is good, for example a flexible document model and ad hoc queries ([ScyllaDB vs MongoDB](https://www.scylladb.com/compare/scylladb-vs-mongodb/)).
- The measured strength of ScyllaDB is predictable p99 latency at high throughput. The maximum throughput under a p99 SLA shows it.
- Use only ScyllaDB sources for claims about ScyllaDB. For background, link the ScyllaDB [comparison pages](https://www.scylladb.com/compare/).
