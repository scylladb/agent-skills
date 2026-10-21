---
title: Workload profile from the application
tags: cassandra-stress, user profile, yaml, columnspec, insert, queries, ops, select-ratio, schema, access patterns
---

# Workload profile from the application

The cassandra-stress default table does not match production. ScyllaDB recommends a benchmark with the production data model, load, and dataset size ([benchmark tips](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/benchmark-tips.md)). Build a YAML user profile from the app, and run it with `user profile=... ops(...)`. The format is in the [cassandra-stress docs](https://docs.scylladb.com/manual/stable/operating-scylla/admin-tools/cassandra-stress.md) and the [example profile](https://github.com/scylladb/cassandra-stress/blob/v4.0.0/examples/cqlstress-example.yaml).

## Collect the facts from the app

Read the repository. Do not guess. Write each fact and the file it came from in the report.

| Fact | Where to find it |
| --- | --- |
| Tables, keys, compaction | `CREATE TABLE` in migrations, `.cql` files, or ORM models |
| Queries on the hot path | Prepared statements in request handlers and workers |
| Consistency level | The driver session config |
| Rows per partition | Bucketing logic, TTL, retention |
| Read/write ratio, rate, data size | Ask the user. Production metrics are better than code. |

Test the tables on the hot path only. A profile has one table. For two hot tables, write two profiles and run them on two loaders at the same time. If the schema has a known anti-pattern, use the `scylladb-data-modeling` skill. Tell the user. Do not change the schema in the benchmark without approval.

## Write the profile

This profile was built from the [care-pet](https://github.com/scylladb/care-pet) Go app (`cpp/data/care-pet-ddl.cql`, `go/handler/avg.go`, `go/cmd/sensor/pet.go`):

```yaml
keyspace: carepet
keyspace_definition: |
  CREATE KEYSPACE carepet WITH replication = {'class': 'NetworkTopologyStrategy', 'AWS_US_EAST_1': 3};
table: measurement
table_definition: |
  CREATE TABLE measurement (
      sensor_id UUID,
      ts        TIMESTAMP,
      value     FLOAT,
      PRIMARY KEY (sensor_id, ts)
  ) WITH compaction = { 'class' : 'TimeWindowCompactionStrategy' };
columnspec:
  - name: ts
    cluster: fixed(1440)          # one reading per minute, one day per sensor
  - name: value
    population: gaussian(30..40)
insert:
  partitions: fixed(1)            # one sensor in each write
  select: fixed(1)/1440           # one row in each write
  batchtype: UNLOGGED
queries:
  read_range:                     # go/handler/avg.go
    cql: SELECT ts, value FROM measurement WHERE sensor_id = ? AND ts >= ? AND ts <= ?
    fields: multirow
```

Rules for each part:

- **`keyspace_definition`**: use `NetworkTopologyStrategy` with the DC name and RF 3. Create the keyspace with `cqlsh` before the first run, with the same statement.
- **`table_definition`**: copy the production statement without changes. cassandra-stress creates the table only if it does not exist.
- **`columnspec`**: `cluster` is the number of rows per partition. `size` sets the bytes of `text` and `blob` values. `population` sets the distinct values. Match the production row size and partition size.
- **`insert`**: `partitions` and `select` set the rows in each write. `select: fixed(1)/<rows per partition>` writes one row. If `batchtype` is not set, the default is `LOGGED`. Set `UNLOGGED` for writes to one partition.
- **`queries`**: copy each hot-path query. Every `?` gets a value from generated rows. `fields: samerow` takes all values from one row, and `multirow` takes them from different rows of the partition. Add the app's `LIMIT` if it has one.

The care-pet app writes several sensors of one pet in one unlogged batch. The profile writes one row in each operation. Write each difference like this in the report.

## Populate the profile

Copy the profile to every loader, and create the keyspace with the same statement as `keyspace_definition`. Then each loader writes its own part of the partitions. `-insert select-ratio=fixed(1)/1` overrides the profile `select`, so each operation writes one full partition. `n` and `-pop seq=` set the partitions:

```sh
while read AZ IP I ID; do scp -q -i $RUN_ID.pem carepet.yaml ec2-user@$IP:profiles/; done < loaders.txt
ssh -i $RUN_ID.pem ec2-user@$L1 'set -a; . ~/bench.env; set +a; $CQLSH ${NODES%%,*} -e "
  CREATE KEYSPACE IF NOT EXISTS carepet WITH replication = {'"'"'class'"'"': '"'"'NetworkTopologyStrategy'"'"', '"'"'$DC'"'"': 3};"'
each 'set -a; . ~/bench.env; set +a; P=10000; LO=$((LOADER * P / LOADERS + 1)); HI=$(((LOADER + 1) * P / LOADERS))
~/cs-run.sh cp-populate user profile=/profiles/carepet.yaml "ops(insert=1)" n=$((HI - LO + 1)) cl=LOCAL_QUORUM \
  -insert "select-ratio=fixed(1)/1" -pop seq=$LO..$HI -rate threads=50'
```

10,000 sensors with 1,440 rows each give 14,400,000 rows.

## Run the profile

Set `CMD` and `POP` for `cs-step.sh` ([cassandra-stress-commands](cassandra-stress-commands.md#run-at-the-target-rate)):

```sh
W="CMD='user profile=/profiles/carepet.yaml ops(insert=3,read_range=1)' POP='dist=uniform(1..10000)'"
each "$W ~/cs-step.sh cp30000-warm 30000 100 1m"
each "$W ~/cs-step.sh cp30000-1 30000 100 3m"; collect cp30000-1 30000
each "$W ~/cs-step.sh cp30000-2 30000 100 3m"; collect cp30000-2 30000   # only for a repeatability check
```

- `ops(insert=3,read_range=1)` is the ratio of operations. Use the ratio that the user gave. Name each query from `queries`, and use `insert` for writes.
- The `-pop` range must match the populated partitions. Otherwise reads return no rows and look fast.
- The summary and the HDR log use the query names as operation types, for example `[insert: ..., read_range: ...]`. Run `~/cs-latency.sh <name> read_range` for the latency of one query.
- Check `Row rate` against `Op rate`. For `read_range`, the row rate shows how many rows each query returned.
