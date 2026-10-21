#!/bin/bash
# Runs on a loader. Runs one cassandra-stress command in Docker and saves the output,
# the HDR log, the loader CPU (vmstat), and the workload options in ~/results.
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
