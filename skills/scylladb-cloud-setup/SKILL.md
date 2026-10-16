---
name: scylladb-cloud-setup
description: Guide users through connecting to a ScyllaDB Cloud cluster, choosing the correct driver and version, and configuring authentication. Use this skill when a user needs to connect to ScyllaDB Cloud, pick a CQL driver, check a driver version, configure credentials, set the default consistency level, size the connection pool, or troubleshoot connection issues. Cluster management through an AI agent goes to scylladb-cloud-mcp. Triggers on "connect to ScyllaDB Cloud", "ScyllaDB connection", "ScyllaDB driver setup", "which driver", "driver version", "Java driver", "Python driver", "CQL connection", "DC-aware load balancing", "ScyllaDB credentials", "connection bundle", "shard-aware", "tablet-aware", "consistency level", "LOCAL_QUORUM", "too many connections".
---

# ScyllaDB Cloud Connection Setup

If the task goes beyond this skill, use the parent `scylladb` skill for a ScyllaDB overview and the list of other ScyllaDB skills. If it is not installed, fetch it from `https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/scylladb/SKILL.md`.

This skill guides users through connecting their application to a ScyllaDB Cloud cluster using the appropriate CQL driver.

## When to Use This Skill

- The user needs to connect an application to a ScyllaDB Cloud cluster for the first time
- The user asks which CQL driver to use for their language, or which driver version
- The user is configuring credentials, contact points, DC-aware load balancing, or the default consistency level
- The user asks why the driver opens so many connections, or wants to change the pool size
- A connection to ScyllaDB Cloud fails or times out
- The user is setting up IP allowlisting or VPC peering

For adjacent topics, use the sibling skill instead:

- Schema and table design after the connection works: `scylladb-data-modeling`
- Vector columns, vector indexes, and driver versions with `vector` type support: `scylladb-vector-search`
- Managing ScyllaDB Cloud clusters from an AI agent: `scylladb-cloud-mcp`
- Self-managed clusters on Kubernetes: `scylladb-kubernetes`
- DynamoDB SDK clients instead of CQL drivers: `scylladb-alternator`

## Overview

Connecting to ScyllaDB Cloud requires:

1. **Cluster credentials** — username, password, and node addresses from the ScyllaDB Cloud Console
2. **A ScyllaDB CQL driver** — installed for the user's programming language

This is an interactive step-by-step guide. The agent detects the user's environment and provides tailored instructions.

## Step 1: Verify the Cluster is Running

Ask the user to confirm they have a ScyllaDB Cloud cluster. If not, direct them to:

1. Go to [cloud.scylladb.com](https://cloud.scylladb.com/) and log in (or sign up)
2. Click **New Cluster** or **Free Trial**
3. Choose AWS or GCP, configure region, instance type, and cluster name
4. Whitelist their IP address
5. (Recommended) Enable VPC Peering during cluster creation — it cannot be enabled later
6. Click **Launch Cluster** and wait for provisioning

Alternatively, for infrastructure-as-code workflows, clusters can be provisioned via the [ScyllaDB Cloud Terraform provider](https://registry.terraform.io/providers/scylladb/scylladbcloud/latest/docs) (`scylladbcloud_cluster` resource), which wraps the same [ScyllaDB Cloud REST API](https://cloud.docs.scylladb.com/stable/api-docs/index.md) used by the Console. This is the better option to suggest when a user is scripting cluster creation rather than clicking through the UI once.

## Step 2: Retrieve Connection Credentials

Guide the user to obtain credentials from the Cloud Console:

1. Go to **My Clusters** → open the cluster
2. Open the **Connect** tab
3. Note the following:
  - **Node addresses** (contact points) — e.g., `node-0.your-cluster.cloud.scylladb.com`
  - **Port** — typically `9042`
  - **Username** — default is `scylla`
  - **Password** — shown on the Connect tab
  - **Datacenter name** — e.g., `AWS_US_EAST_1`

**Do not ask for or handle credentials directly** — guide the user to retrieve them from the Console and store them securely (environment variables, secrets manager, etc.).

## Step 3: Determine the Driver

Ask the user which programming language they are using so you can recommend the correct ScyllaDB CQL driver:

| Language | Driver                                   | Package                                            |
| -------- | ----------------------------------------- | --------------------------------------------------- |
| Python   | scylla-driver                             | `pip install scylla-driver`                        |
| Java     | java-driver (ScyllaDB's fork, 4.x line)   | `com.scylladb:java-driver-core:4.19.2.2` (Maven). Requires Java 11+ (Java 8 support was dropped in 4.19.2.0). |
| Go       | gocql (ScyllaDB fork)                     | `replace github.com/gocql/gocql => github.com/scylladb/gocql v1.20.0` in `go.mod` |
| Rust     | scylla-rust-driver                        | `cargo add scylla`                                 |
| C#       | scylla-csharp-driver                      | NuGet package                                      |
| C++      | cpp-rust-driver                           | Build from source or vcpkg                         |
| Node.js  | scylla-node-driver                        | `npm install @scylladb/driver`                     |

⚠️ **Important**: ScyllaDB has its own driver forks — do **not** use the DataStax/Cassandra drivers - unless there's no ScyllaDB driver available for your language. ScyllaDB drivers are shard-aware: they send each request to the CPU core that owns the data. They are also tablet-aware: they learn tablet replica placement from the server and send requests on tablet tables straight to the correct node and shard.

New keyspaces use [tablets by default](https://docs.scylladb.com/manual/stable/architecture/tablets.md). A driver version without tablet support cannot route requests on these tables directly, so each request can take an extra hop. Use at least the minimum version with tablet support from the [driver docs](https://docs.scylladb.com/stable/drivers/cql-drivers.md): Python 3.26.5, Java 4.18.0 (3.x line: 3.11.5.2), Go 1.13.0, Rust 0.13.0, all versions of C#, CPP RS, and Node.js RS.

For Go, recommend gocql. `gocqlx` is an optional wrapper on top of gocql, and the driver docs mark it as not supported for tablets and the `vector` type. See the Go notes in [driver-configuration](references/driver-configuration.md#go-gocql).

## Step 4: Configure the Connection

Consult [driver-configuration](references/driver-configuration.md) for per-language connection snippets.

**Critical requirements for ScyllaDB Cloud:**

**Authentication** — `PlainTextAuthProvider` with the username and password from Step 2.

**Token-aware load balancing** — when you set a DC-aware policy in Python, Go, or C#, wrap it in the token-aware policy. A bare DC-aware policy turns off token-aware routing, so shard-aware and tablet-aware routing do not apply. The Java 4.x and Rust default policies are token-aware.

**Consistency level** — set `LOCAL_QUORUM` as the session default for reads and writes. ScyllaDB [recommends `LOCAL_QUORUM`](https://docs.scylladb.com/manual/stable/operating-scylla/procedures/tips/production-readiness.md) for single-DC and multi-DC clusters. In a single DC it waits for the same number of replicas as `QUORUM`. Driver defaults differ: Python, Java 4.x, and C# use `LOCAL_ONE`, gocql uses `QUORUM`, Rust uses `LOCAL_QUORUM`. Use `LOCAL_ONE` only for reads that can return stale data.

Consult [cloud-connection](references/cloud-connection.md) for details on IP allowlisting and VPC peering.

## Step 5: Test the Connection

Provide a minimal test query for the user's driver language:

```
SELECT release_version FROM system.local;
```

If this query returns a version string, the connection is working. If it fails, check:

1. **IP not allowlisted** — verify the client IP is in the cluster's Allowed IPs list
2. **Wrong datacenter name** — must match exactly (e.g., `AWS_US_EAST_1`, not `us-east-1`)
3. **Wrong port** — ensure port 9042 is used
4. **Firewall/VPN blocking** — ensure outbound TCP on port 9042 is allowed
5. **Using Cassandra driver instead of ScyllaDB driver** — the DataStax drivers lack shard-aware and tablet-aware routing and may have compatibility issues

## Step 6: Next Steps

Once connected, suggest relevant next steps:

- **Data modeling**: Use the `scylladb-data-modeling` skill for schema design guidance
- **Vector search**: Use the `scylladb-vector-search` skill if they need similarity search
- **Prepared statements**: Recommend using prepared statements for all frequently-run queries (reduces parsing overhead, enables token-aware routing). See [prepared-statements](references/prepared-statements.md) for the full pattern with examples.
- **Connection count**: a shard-aware driver opens one connection per shard on each node. This is expected. Do not reduce the pool size to lower the count. If many client processes on one host each open a session (for example, pre-fork web server workers), see [connection pooling](references/driver-configuration.md#connection-pooling).
- **Infrastructure as code**: If the user wants to manage cluster provisioning declaratively (not just connect an app to an existing cluster), point them to the [ScyllaDB Cloud Terraform provider](https://registry.terraform.io/providers/scylladb/scylladbcloud/latest/docs) rather than only the manual Console flow in Step 1.
- **ScyllaDB Cloud MCP server**: If the user wants to manage their ScyllaDB Cloud clusters through an AI agent, use the `scylladb-cloud-mcp` skill.

## Quick Reference

- [cloud-connection](references/cloud-connection.md) — Connection parameters, IP allowlisting, VPC peering, the Cloud datacenter naming convention, and common connection errors. Consult when a connection fails, or before allowlisting a client IP or setting up VPC peering.
- [driver-configuration](references/driver-configuration.md) — Connection code for each ScyllaDB driver (Python, Java, Go, Rust, C#, Node.js, C++) with `PlainTextAuthProvider`, token-aware DC-aware load balancing, and `LOCAL_QUORUM`, plus connection pool notes. Consult when writing or reviewing the connection code for the user's language, or when the user asks about the number of connections.
- [prepared-statements](references/prepared-statements.md) — Why prepared statements are required for token-aware and shard-aware routing, with incorrect and correct examples. Consult when the application runs the same query repeatedly, or when reviewing code that builds CQL strings at runtime.
