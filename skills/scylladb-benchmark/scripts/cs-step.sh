#!/bin/bash
# Runs on a loader. Runs one step at a total rate, split across the loaders, with cs-run.sh.
# Usage: ~/cs-step.sh <name> <total ops/s> <threads per loader> <duration>
# Set CMD and POP to change the workload. Default: mixed 50/50 over all rows.
set -a; . ~/bench.env; set +a
CMD=${CMD:-"mixed ratio(write=1,read=1)"}; POP=${POP:-"dist=uniform(1..$ROWS)"}
exec ~/cs-run.sh "$1" $CMD duration=$4 cl=LOCAL_QUORUM -pop "$POP" \
  -rate threads=$3 fixed=$(($2 / LOADERS))/s
