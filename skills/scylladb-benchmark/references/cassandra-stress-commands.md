---
title: cassandra-stress commands for a ScyllaDB Cloud benchmark
tags: cassandra-stress, docker, cqlsh, keyspace, populate, fixed rate, mixed, warm-up, interval log, rate steps, multiple loaders, rack-aware, tls
---

# cassandra-stress commands for a ScyllaDB Cloud benchmark

These commands were run with `scylladb/cassandra-stress:4.0.0` on 2026-10-20. Check option names in the [source](https://github.com/scylladb/cassandra-stress/tree/v4.0.0/src/java/org/apache/cassandra/stress/settings). They need `each`, `loaders.txt`, and `~/bench.env` from [loader-vm-aws](loader-vm-aws.md#prepare-the-loaders).

Contents: [helpers](#install-the-helpers), [keyspace](#create-the-keyspace), [populate](#populate), [target rate](#run-at-the-target-rate), [results](#read-the-results), [interval log](#read-the-interval-log), [step search](#find-the-maximum-rate-with-a-step-search), [TLS](#tls).

## Install the helpers

`cs-run.sh` adds the connection and log options, waits, and saves the output, the HDR log, the loader CPU, and the workload options in `~/results`. `-d` keeps a run alive if SSH drops. `--network=host` removes the Docker network overhead ([README](https://github.com/scylladb/cassandra-stress#performance-penalty)). `cs-step.sh` runs one run at a total rate, split across the loaders.

```sh
cat > cs-run.sh <<'EOF'
#!/bin/bash
# Usage: ~/cs-run.sh <name> <cassandra-stress command and workload options>
set -u
NAME=$1; shift
set -a; . ~/bench.env; set +a
R=$HOME/results; mkdir -p "$R" ~/profiles
vmstat -n 5 > "$R/$NAME.vmstat" & VMSTAT=$!
date -u +%FT%TZ > "$R/$NAME.start"
echo "$*" > "$R/$NAME.cmd"
docker run -d --name "cs-$NAME" --network=host \
  -v "$R":/results -v "$HOME/profiles":/profiles:ro "$CS_IMAGE" "$@" \
  -node "$NODES" datacenter="$DC" rack="$RACK" \
  -mode native cql3 user=scylla password="$(cat ~/.scylladb_password)" \
  -log interval=10s file="/results/$NAME.log" hdrfile="/results/$NAME.hdr" > /dev/null
RC=$(docker wait "cs-$NAME")
date -u +%FT%TZ > "$R/$NAME.end"
kill $VMSTAT
docker logs "cs-$NAME" > "$R/$NAME.out" 2>&1
docker rm "cs-$NAME" > /dev/null
echo "$RC" > "$R/$NAME.exit"
echo "$NAME exit=$RC"
EOF
cat > cs-step.sh <<'EOF'
#!/bin/bash
# Usage: ~/cs-step.sh <name> <total ops/s> <threads per loader> <duration>
# Set CMD and POP to change the workload. Default: mixed 50/50 over all rows.
set -a; . ~/bench.env; set +a
CMD=${CMD:-"mixed ratio(write=1,read=1)"}; POP=${POP:-"dist=uniform(1..$ROWS)"}
exec ~/cs-run.sh "$1" $CMD duration=$4 cl=LOCAL_QUORUM -pop "$POP" \
  -rate threads=$3 fixed=$(($2 / LOADERS))/s
EOF
while read AZ IP I ID; do scp -q -i $RUN_ID.pem cs-run.sh cs-step.sh ec2-user@$IP: ; done < loaders.txt
each 'chmod +x ~/cs-*.sh'
```

The log line `Using provided rack name 'use1-az2' for RackAwareRoundRobinPolicy` confirms rack-aware routing. The warning `Some contact points don't match local rack` is expected. Also install `cs-latency.sh` and `cs-row.sh` from [results-and-report](results-and-report.md).

## Create the keyspace

The cassandra-stress schema default is RF 1. Create the keyspace with `cqlsh` from a credentials file, so the password is not on the `cqlsh` command line. The `scylladb/scylla` image runs as user 998, so `--user` is necessary to read the mode 600 file.

```sh
each 'umask 077; mkdir -p ~/.cassandra
printf "[PlainTextAuthProvider]\nusername = scylla\npassword = %s\n" "$(cat ~/.scylladb_password)" > ~/.cassandra/credentials
printf "[authentication]\ncredentials = /cass/credentials\n" > ~/.cassandra/cqlshrc
echo "CQLSH=\"docker run --rm --network=host --user $(id -u):$(id -g) -e HOME=/tmp -v \$HOME/.cassandra:/cass:ro -v \$HOME/profiles:/profiles:ro --entrypoint cqlsh scylladb/scylla:2026.3 --cqlshrc /cass/cqlshrc\"" >> ~/bench.env'
L1=$(awk 'NR == 1 {print $2}' loaders.txt)
ssh -i $RUN_ID.pem ec2-user@$L1 'set -a; . ~/bench.env; set +a; $CQLSH ${NODES%%,*} -e "
  CREATE KEYSPACE IF NOT EXISTS keyspace1 WITH replication = {'"'"'class'"'"': '"'"'NetworkTopologyStrategy'"'"', '"'"'$DC'"'"': 3};"'
```

cassandra-stress runs `CREATE KEYSPACE IF NOT EXISTS`, so it keeps your keyspace. Its settings block still prints `{replication_factor=1}`. Tablets are on by default for new keyspaces ([tablets](https://docs.scylladb.com/manual/stable/architecture/tablets.md)).

## Populate

Each loader writes its own part of the key range:

```sh
each 'echo ROWS=20000000 >> ~/bench.env; set -a; . ~/bench.env; set +a
LO=$((LOADER * ROWS / LOADERS + 1)); HI=$(((LOADER + 1) * ROWS / LOADERS))
~/cs-run.sh populate write n=$((HI - LO + 1)) cl=LOCAL_QUORUM -pop seq=$LO..$HI -rate threads=300'
```

Populate has no rate limit. Its `Op rate` and `Latency mean` are the first measurement of the cluster. For a different row size, add `-col n=FIXED(1) size=FIXED(1024)` to every run.

## Run at the target rate

Warm up once, then measure twice. Discard the warm-up. The built-in warm-up of each run is only 50,000 operations, so it does not fill the cache. Set `-pop` on every read and mixed run. Without it, reads use `gaussian(1..1000000)`.

```sh
TARGET=220000; T=400          # default recipe. For other targets, get T from results-and-report.md#plan-the-load
each "~/cs-step.sh t$TARGET-warm $TARGET $T 1m"
each "~/cs-step.sh t$TARGET-1 $TARGET $T 3m"; collect t$TARGET-1 $TARGET       # tell the user now
each "~/cs-step.sh t$TARGET-2 $TARGET $T 3m"; collect t$TARGET-2 $TARGET
```

`collect` is in [results-and-report](results-and-report.md#collect-the-results-of-all-loaders). When the first measured run is valid and its p99 is within the SLA, tell the user the rate and the p99 at once. Then finish the second run. For a user profile, set `CMD` and `POP` ([workload-profile](workload-profile.md#run-the-profile)). For a sizing decision, run 30 min or more, long enough for compactions ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)).

## Read the results

`sed -n '/^Results:/,$p' ~/results/<name>.out` prints the summary of one loader: `Op rate`, `Latency mean`, `median`, `95th`, `99th`, `99.9th`, and `max`, in total and per operation type. It has no p90.

- Values have thousands separators (`16,877.9 ms`). Remove the commas before you compare.
- With `fixed=`, the latency starts at the scheduled time, so it includes the time in the queue.
- A failed run prints no `Results:` block, and `~/results/<name>.exit` is not 0. Read the end of the `.out` file.
- `Failed to create client too many times` and then `Failed to execute warmup` mean that the client could not connect. Check the route, the firewall rule, and the password.

## Read the interval log

`-log interval=10s` writes one `total,` line every 10 s: type, total ops, op/s, pk/s, row/s, mean, med, .95, .99, .999, max, time, stderr, errors. Print the intervals that broke a 10 ms SLA:

```sh
each 'awk -F", *" -v s=10 '"'"'$1 == "total" && $9 + 0 > s {print $12 " s: p99 " $9 " ms"}'"'"' ~/results/<name>.log'
```

One stall of a few seconds sets the p99 of a short run. Report each stall with its UTC time, so the user can check the same window in the Monitoring tab.

## Find the maximum rate with a step search

Use a step search for a shape that has no measured recipe, or when the user asks for it.

1. Start well below the populate rate. Use steps of equal size.
2. For each step, run the warm-up and two measured runs. Do not populate again.
3. Stop at the first step where a run breaks the SLA or a validity rule ([results-and-report](results-and-report.md#validity-rules)).
4. After a step that saturates the cluster, wait until compactions end in the Monitoring tab. Then go down one step.
5. Report the highest step that passed every run. The [i8g blog](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/) defines "max throughput under SLA" as the maximum rate at p99 below 10 ms.

## TLS

Port 9042 accepts unencrypted connections unless **Ensure encrypted connections** is on. Then use port 9142 ([client-to-node encryption](https://cloud.docs.scylladb.com/stable/security/client-to-node-encryption.md)). Convert the cluster CA file to a truststore with `keytool -importcert` (the image has `keytool`). Add `-port native=9142 -transport truststore=/work/truststore.jks truststore-password=<password>` to each run, and mount the file at `/work`.
