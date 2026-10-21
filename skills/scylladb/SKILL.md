---
name: scylladb
description: Overview of ScyllaDB and a map of the ScyllaDB agent skills, with instructions to install or fetch a skill that is missing. Use this skill when starting a project on ScyllaDB or moving an existing project to ScyllaDB, when a task covers more than one ScyllaDB area, or when no more specific ScyllaDB skill matches. Child skill scylladb-data-modeling wins for CQL schemas, keys, indexes, TTL, and compaction. Child skill scylladb-cloud-setup wins for connections, drivers, and credentials. Also use to find the skill for vector search, the DynamoDB API (Alternator), Kubernetes and the ScyllaDB Operator, the ScyllaDB Cloud MCP server, or benchmarks and load tests of ScyllaDB Cloud. Triggers on "ScyllaDB", "Scylla", "ScyllaDB Cloud", "get started with ScyllaDB", "use ScyllaDB", "migrate to ScyllaDB", "switch to ScyllaDB".
---

# ScyllaDB

ScyllaDB is a [distributed NoSQL wide-column database](https://docs.scylladb.com/manual/stable/index.md) for data-intensive applications that need high throughput and low latency. Applications reach it through CQL or through Alternator, a DynamoDB-compatible API. It runs as ScyllaDB Cloud (fully managed), on Kubernetes with the ScyllaDB Operator, or on your own Linux servers.

Developers pick ScyllaDB for low, predictable latency (e.g. 1ms p99) at high throughput (e.g. 1 million ops/sec), horizontal scaling by adding nodes, high availability with no single point of failure, global distribution through multi-datacenter replication, and a shard-per-core architecture.

## When to Use This Skill

- Starting a new project on ScyllaDB
- Moving an existing project from another database to ScyllaDB
- The task covers more than one area
- No child skill below matches the task

## How to Run ScyllaDB

**Production, recommended: [ScyllaDB Cloud](https://cloud.docs.scylladb.com/stable/index.md).** A fully managed service on AWS or GCP, in ScyllaDB's cloud account or in the user's own (Bring Your Own Account). ScyllaDB operates the nodes, repairs, backups, and upgrades. Choose CQL or Alternator when you create a cluster. Create clusters in the Cloud UI, the Cloud API, or through the `scylladb-cloud-mcp` skill. Connect applications with the `scylladb-cloud-setup` skill. A [free trial](https://cloud.docs.scylladb.com/stable/cloud-services/free-trial.md) is available.

**Production, self-hosted:** on Kubernetes with the [ScyllaDB Operator](https://operator.docs.scylladb.com/stable/index.md) (the `scylladb-kubernetes` skill), or [installed on Linux VMs or bare metal](https://docs.scylladb.com/manual/stable/getting-started/install-scylla/index.md). Add ScyllaDB Manager and the Monitoring Stack (see Tools). Since 2025.1 ScyllaDB is one source-available product; the separate Open Source and Enterprise editions are gone. See [version support](https://docs.scylladb.com/stable/versioning/version-support.md).

**Local testing: Docker.** This is the easiest and quickest way to spin up a node, and it is not for production. ScyllaDB takes all CPUs and memory of the host by default, so limit it:

```sh
docker run --name scylla -d -p 9042:9042 scylladb/scylla --smp 1 --memory 1G
```

- The image runs in developer mode by default, which skips the production checks. See [Run ScyllaDB in Docker](https://docs.scylladb.com/manual/stable/getting-started/install-scylla/run-in-docker.md).
- A single node holds one replica, so use replication factor 1 in its keyspaces.

## APIs

- **CQL** — the primary API: a query language and binary protocol, used through the [ScyllaDB drivers](https://docs.scylladb.com/stable/drivers/cql-drivers.md). [CQL reference](https://docs.scylladb.com/manual/stable/cql/index.md).
- **Alternator** — the [DynamoDB-compatible API](https://docs.scylladb.com/manual/stable/alternator/alternator.md), JSON over HTTP. Alternator tables are ordinary ScyllaDB tables.

## Features

- **Vector Search** — [ANN queries over vector columns](https://cloud.docs.scylladb.com/stable/vector-search/index.md). ScyllaDB Cloud only for production; runs locally in Docker for testing.

## Tools

- **ScyllaDB Cloud MCP server** — [exposes the ScyllaDB Cloud API](https://cloud.docs.scylladb.com/stable/api-docs/mcp.md) as tools for AI agents. Beta.
- **ScyllaDB Manager** — [schedules repairs and backups](https://manager.docs.scylladb.com/stable/index.md) on self-hosted clusters.
- **ScyllaDB Monitoring Stack** — [Prometheus and Grafana dashboards](https://monitoring.docs.scylladb.com/stable/index.md) for self-hosted clusters.

## ScyllaDB Documentation

- Find pages through the indexes; do not guess URLs: https://docs.scylladb.com/llms.txt, https://docs.scylladb.com/manual/stable/llms.txt, https://cloud.docs.scylladb.com/llms.txt
- Fetch pages as Markdown: replace `.html` with `.md`, use `index.md` for a directory URL.

## Choosing the Right Skill

When the task matches a row, work from that skill and not from this overview.

| Skill | Use it for |
| --- | --- |
| `scylladb-cloud-setup` | Connecting to ScyllaDB Cloud, choosing a driver and version, credentials, connection problems. |
| `scylladb-data-modeling` | Designing or reviewing CQL schemas, partition and clustering keys, secondary indexes, materialized views, TTL, tombstones, compaction. |
| `scylladb-vector-search` | Embeddings, vector indexes, ANN queries, RAG on ScyllaDB Cloud. |
| `scylladb-alternator` | DynamoDB-compatible API, porting DynamoDB applications, boto3 and AWS SDK clients. |
| `scylladb-kubernetes` | ScyllaDB Operator, ScyllaCluster, running ScyllaDB on Kubernetes. |
| `scylladb-cloud-mcp` | Managing ScyllaDB Cloud clusters through the Cloud MCP server. |
| `scylladb-benchmark` | Benchmarks and load tests of ScyllaDB Cloud with cassandra-stress, p50/p90/p99 latency, maximum throughput under an SLA. |

## Installing the Right Skill

1. Check whether the skill is already installed (it appears in the available skills list, or its `SKILL.md` is present). If it is, use it.
2. If it is not installed, show the user this command and ask them to run it:

   ```sh
   npx skills add scylladb/agent-skills --skill <skill-name>
   ```

   Useful flags: `-g` (install globally), `-a <agent>` (target agent), `-y` (skip prompts).
3. Newly installed skills can load only in the next session. To use the skill now, fetch its `SKILL.md` and follow it:

   ```
   https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/<skill-name>/SKILL.md
   ```

   Fetch its references from the same path, under `references/`. If Node.js is available, `npx skills use scylladb/agent-skills@<skill-name>` prints the skill as a prompt without installing it.
