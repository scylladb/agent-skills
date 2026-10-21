---
title: Percentiles, results table, and validity rules
tags: hdr, hdrhistogram, HistogramLogProcessor, p50, p90, p99, multiple loaders, merge, variance, validity, client-side latency, server-side latency, threads, dataset
---

# Percentiles, results table, and validity rules

Contents: [plan](#plan-the-load), [percentiles](#get-p50-p90-and-p99), [results row](#make-the-results-row), [collect](#collect-the-results-of-all-loaders), [validity](#validity-rules), [latency source](#client-side-and-server-side-latency).

## Plan the load

- **Published results**: 3 × i4i.4xlarge, RF 3, `QUORUM`, p99 below 10 ms gave 750,000 cached reads/s, 210,000 non-cached reads/s, and 150,000 writes/s ([i8g blog](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/)).
- **Floor**: expect at least 12,500 ops/s for each physical core, for payloads up to 1 KB ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). On x86, one vCPU is half a physical core ([i8g blog](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/)).
- **Threads**: each cassandra-stress thread waits for one reply. Use `threads per loader ≈ rate per loader × mean latency × 2`, with the mean from populate. Do not use many more. In an earlier test of this skill, ten times too many threads gave client stalls of several seconds with no errors. If `Op rate` falls below `fixed=` while loader CPU is low, add threads.
- **Dataset**: a dataset smaller than production can give wrong results ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). Raw data per node is about `rows × row bytes × RF / nodes`. The default row is 10 bytes of key and 5 × 34 bytes of values. If the data is smaller than the node RAM, reads come from cache. Say "cached" or "disk" in the report.

## Get p50, p90, and p99

The summary has no p90. The HDR log has one histogram for each operation type and 10 s interval, with the tags `<op>-rt` (response time from the scheduled start), `<op>-st` (service time), and `<op>-wt` (wait time). `cs-latency.sh` merges the `-rt` histograms of all loaders with `HistogramLogProcessor` from the HdrHistogram jar in the image. On one loader, its p50, p99, and max match the summary. Values are in ms. The image has no `javac`, so a custom Java tool does not run in it.

```sh
cat > cs-latency.sh <<'EOF'
#!/bin/bash
# Usage: ~/cs-latency.sh <name> [op]   op: READ, WRITE, or a profile query name. Default: all.
# Merges the response-time (-rt) intervals of <name>.hdr and of copies from other loaders (<name>@*.hdr).
set -eu
NAME=$1; OP=${2:-[^,]*}
cd ~/results
grep -v '^Tag=' "$NAME.hdr" | grep -v '^[0-9]' > "$NAME.sel.hdr"
cat "$NAME.hdr" $(ls "$NAME"@*.hdr 2>/dev/null) | grep "^Tag=$OP-rt," | sed 's/^Tag=[^,]*,//' >> "$NAME.sel.hdr"
docker run --rm -v "$HOME/results":/results --entrypoint java scylladb/cassandra-stress:4.0.0 \
  -cp /usr/local/share/cassandra-stress/lib/HdrHistogram-2.2.2.jar \
  org.HdrHistogram.HistogramLogProcessor -i "/results/$NAME.sel.hdr" -o "/results/$NAME.sel" > /dev/null
awk '$1 ~ /^[0-9.]+$/ {
       if (!a && $2 >= 0.50) {p50=$1; a=1}
       if (!b && $2 >= 0.90) {p90=$1; b=1}
       if (!c && $2 >= 0.99) {p99=$1; c=1} }
     /^#\[Max/ {gsub(/[],]/, ""); max=$3; n=$NF}
     END {printf "p50=%s p90=%s p99=%s max=%s count=%s\n", p50, p90, p99, max, n}' "$NAME.sel.hgrm"
rm -f "$NAME.sel.hdr" "$NAME.sel" "$NAME.sel.hgrm"
EOF
```

## Make the results row

`cs-row.sh` prints one row: run, loaders, target, measured ops/s (sum), p50, p90, p99, max (ms, merged), errors (sum), loader CPU (highest), and flags.

```sh
cat > cs-row.sh <<'EOF'
#!/bin/bash
# Usage: ~/cs-row.sh <name> <total target rate>   Prints one row of the results table.
# Adds the copies from other loaders (<name>@*.out, .vmstat, .exit, .hdr) when they exist.
set -u
NAME=$1; RATE=$2; cd ~/results
F=$(ls "$NAME".out "$NAME"@*.out 2>/dev/null)
sum() { for f in $F; do sed -n "s/^$1 *: *\([0-9,.]*\).*/\1/p" "$f" | tr -d ,; done | awk '{s += $1} END {print s + 0}'; }
OPR=$(sum 'Op rate'); ERR=$(sum 'Total errors'); N=$(echo "$F" | wc -w)
[ "$(grep -c '^Total errors' $F | awk -F: '{s += $NF} END {print s}')" = "$N" ] || ERR=none
# Skip the first 30 s: JVM start and the built-in warm-up run without a rate limit.
CPU=$(cat "$NAME".vmstat "$NAME"@*.vmstat 2>/dev/null | awk '$1 == "procs" {k = 0} {k++} $15 ~ /^[0-9]+$/ && k > 8 {c = 100 - $15; if (c > m) m = c} END {print m + 0}')
LAT=$(~/cs-latency.sh "$NAME" | sed 's/ count=.*//; s/[a-z0-9]*=//g')
FLAGS=""
[ "$(cat "$NAME".exit "$NAME"@*.exit 2>/dev/null | sort -u)" = 0 ] || FLAGS="$FLAGS exit-code"
awk -v o="$OPR" -v r="$RATE" 'BEGIN {exit !(o < 0.97 * r)}' && FLAGS="$FLAGS rate<97%"
[ "$ERR" = 0 ] || FLAGS="$FLAGS errors"
[ "$CPU" -le 50 ] || FLAGS="$FLAGS loader-cpu>50%"
printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s%% |%s |\n" "$NAME" "$N" "$RATE" "$OPR" \
  $LAT "$ERR" "$CPU" "${FLAGS:- valid}"
EOF
while read AZ IP I ID; do scp -q -i $RUN_ID.pem cs-latency.sh cs-row.sh ec2-user@$IP: ; done < loaders.txt
each 'chmod +x ~/cs-*.sh'
```

For a user profile, also run `~/cs-latency.sh <name> <query>` for each query name.

## Collect the results of all loaders

`collect` copies the files of each run from the other loaders to the first loader as `<name>@<AZ ID>.*`, then prints the row. Percentiles are merged, never averaged ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).

```sh
collect() { L1=$(awk 'NR == 1 {print $2}' loaders.txt)
  while read AZ IP I ID; do [ "$I" = 0 ] && continue
    ssh -n -i $RUN_ID.pem ec2-user@$IP "cd results && tar cf - $1.out $1.vmstat $1.exit $1.hdr" \
      | ssh -i $RUN_ID.pem ec2-user@$L1 "cd results && tar xf - --transform 's/^$1\./$1@$AZ./'"
  done < loaders.txt
  ssh -n -i $RUN_ID.pem ec2-user@$L1 "~/cs-row.sh $1 $2"; }
```

## Validity rules

Mark a run invalid, and say why in the report, if one of these is true:

- The exit code is not 0 on a loader, or `Total errors` is not 0.
- The measured rate is below 97% of the target. The loaders or the cluster could not keep the schedule.
- The CPU of a loader was above 50% ([benchmarking tutorial](https://github.com/scylladb/scylladb/wiki/Benchmarking-Tutorial)).
- The cluster is a local Docker container, or a loader ran on a laptop or a cluster node ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).
- The node count or the `instanceId` of the X Cloud cluster changed during the run.

A run through the public IP allowlist can be valid. Mark it "public network path" in the report.

For each step, give the spread of the runs: `(max − min) / min` of the measured rate and of p99. If the runs differ, find the cause before you report the step. Old data from an earlier test is one cause ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).

## Client-side and server-side latency

The table has client-side latency: the loader queue, the network, the driver, and the server. Server-side latency is in the cluster **Monitoring** tab ([monitor a cluster](https://cloud.docs.scylladb.com/stable/operate/monitor-cluster.md)). Give the user the UTC window of each run from the `.start` and `.end` files. The Cloud MCP tool `monitor_cluster` has no p99, so do not report it as p99.
