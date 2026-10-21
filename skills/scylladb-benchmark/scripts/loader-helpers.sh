#!/bin/bash
# Runs on the developer machine. Defines the shell functions each and collect.
# Usage: . "$SKILL_DIR/scripts/loader-helpers.sh"   Source it again in each new shell.
# Needs RUN_ID, the key file $RUN_ID.pem, and loaders.txt in the current directory.
# loaders.txt columns: AZ ID, public IP, index, instance ID.
#
#   each '<command>'                       Runs the command on all loaders at the same time.
#   collect <name> <total target rate>     Copies the files of run <name> from the other loaders
#                                          to the first loader as <name>@<AZ ID>.*, then prints
#                                          the results row (cs-row.sh).
#
# ssh -n keeps ssh from reading the loaders.txt loop input. Do not use -n when you send a file on stdin.

each() { while read AZ IP I ID; do ssh -n -i $RUN_ID.pem -o StrictHostKeyChecking=accept-new \
  ec2-user@$IP "$1" | sed "s/^/[$AZ] /" & done < loaders.txt; wait; }

collect() { L1=$(awk 'NR == 1 {print $2}' loaders.txt)
  while read AZ IP I ID; do [ "$I" = 0 ] && continue
    ssh -n -i $RUN_ID.pem ec2-user@$IP "cd results && tar cf - $1.out $1.vmstat $1.exit $1.hdr" \
      | ssh -i $RUN_ID.pem ec2-user@$L1 "cd results && tar xf - --transform 's/^$1\./$1@$AZ./'"
  done < loaders.txt
  ssh -n -i $RUN_ID.pem ec2-user@$L1 "~/cs-row.sh $1 $2"; }
