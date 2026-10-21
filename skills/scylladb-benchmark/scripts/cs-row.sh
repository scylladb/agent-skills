#!/bin/bash
# Runs on a loader. Prints one row of the results table: run, loaders, target, measured ops/s (sum),
# p50, p90, p99, max (ms, merged), errors (sum), loader CPU (highest), and flags.
# Usage: ~/cs-row.sh <name> <total target rate>
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
