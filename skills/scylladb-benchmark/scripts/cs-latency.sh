#!/bin/bash
# Runs on a loader. Prints p50, p90, p99, and max in ms, merged from the HDR logs of all loaders.
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
