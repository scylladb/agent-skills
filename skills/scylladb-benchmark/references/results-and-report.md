---
title: Percentiles, results table, and validity rules
tags: hdr, hdrhistogram, HistogramLogProcessor, p50, p90, p99, multiple loaders, merge, variance, validity, client-side latency, server-side latency, threads, dataset
---

# Percentiles, results table, and validity rules

Contents: [plan](#plan-the-load), [percentiles](#get-p50-p90-and-p99), [results row](#make-the-results-row), [validity](#validity-rules), [latency source](#client-side-and-server-side-latency).

## Plan the load

- **Published results**: 3 × i4i.4xlarge, RF 3, `QUORUM`, p99 below 10 ms gave 750,000 cached reads/s, 210,000 non-cached reads/s, and 150,000 writes/s ([i8g blog](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/)).
- **Floor**: expect at least 12,500 ops/s for each physical core, for payloads up to 1 KB ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). On x86, one vCPU is half a physical core ([i8g blog](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/)).
- **Threads**: each cassandra-stress thread waits for one reply. Use `threads per loader ≈ rate per loader × mean latency × 2`, with the mean from populate. Do not use many more: too many threads cause client stalls with no errors. If `Op rate` falls below `fixed=` while loader CPU is low, add threads.
- **Dataset**: a dataset smaller than production can give wrong results ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). Raw data per node is about `rows × row bytes × RF / nodes`. The default row is 10 bytes of key and 5 × 34 bytes of values. If the data is smaller than the node RAM, reads come from cache. Say "cached" or "disk" in the report.

## Get p50, p90, and p99

The summary has no p90. The HDR log has one histogram for each operation type and 10 s interval, with the tags `<op>-rt` (response time from the scheduled start), `<op>-st` (service time), and `<op>-wt` (wait time). [cs-latency.sh](../scripts/cs-latency.sh) merges the `-rt` histograms of all loaders with `HistogramLogProcessor` from the HdrHistogram jar in the image. It prints p50, p90, p99, and max in ms.

```sh
~/cs-latency.sh <name> [op]     # on the first loader, after collect. op: READ, WRITE, or a profile query name
```

For a user profile, run it for each query name.

## Make the results row

`collect <name> <total target rate>` from [loader-helpers.sh](../scripts/loader-helpers.sh) copies the files of a run from the other loaders to the first loader as `<name>@<AZ ID>.*`. Then it runs [cs-row.sh](../scripts/cs-row.sh) there. The row has: run, loaders, target, measured ops/s (sum), p50, p90, p99, max (ms, merged), errors (sum), loader CPU (highest), and flags. Percentiles are merged, never averaged ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).

```sh
collect t220000-1 220000
```

## Validity rules

Mark a run invalid, and say why in the report, if one of these is true:

- The exit code is not 0 on a loader, or `Total errors` is not 0.
- The measured rate is below 97% of the target. The loaders or the cluster could not keep the schedule.
- The CPU of a loader was above 50% ([benchmarking tutorial](https://github.com/scylladb/scylladb/wiki/Benchmarking-Tutorial)).
- The cluster is a local Docker container, or a loader ran on a laptop or a cluster node ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).
- The node count or the `instanceId` of the X Cloud cluster changed during the run.

A run through the public IP allowlist can be valid. Mark it "public network path" in the report.

If you measured a step more than once, give the spread of the runs: `(max − min) / min` of the measured rate and of p99. If the runs differ, find the cause before you report the step. Old data from an earlier test is one cause ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). A run soon after populate can fail on stalls, so repeat a failed run once.

## Client-side and server-side latency

The table has client-side latency: the loader queue, the network, the driver, and the server. Server-side latency is in the cluster **Monitoring** tab ([monitor a cluster](https://cloud.docs.scylladb.com/stable/operate/monitor-cluster.md)). Give the user the UTC window of each run from the `.start` and `.end` files. The Cloud MCP tool `monitor_cluster` has no p99, so do not report it as p99.
