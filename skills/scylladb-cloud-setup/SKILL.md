---
name: scylladb-cloud-setup
description: Guide users through connecting to a ScyllaDB Cloud cluster, choosing the correct driver and version, and configuring authentication. Use this skill when a user needs to connect to ScyllaDB Cloud, pick a CQL driver, check a driver version, configure credentials, or troubleshoot connection issues. Triggers on "connect to ScyllaDB Cloud", "ScyllaDB connection", "ScyllaDB driver setup", "which driver", "driver version", "Java driver", "Python driver", "CQL connection", "DC-aware load balancing", "ScyllaDB credentials", "connection bundle".
---

# ScyllaDB Cloud Connection Setup

This skill guides users through connecting their application to a ScyllaDB Cloud cluster using the appropriate CQL driver.

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

Alternatively, for infrastructure-as-code workflows, clusters can be provisioned via the [ScyllaDB Cloud Terraform provider](https://registry.terraform.io/providers/scylladb/scylladbcloud/latest/docs) (`scylladbcloud_cluster` resource), which wraps the same [ScyllaDB Cloud REST API](https://cloud.docs.scylladb.com/stable/api-docs/) used by the Console. This is the better option to suggest when a user is scripting cluster creation rather than clicking through the UI once.

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
| Java     | java-driver (ScyllaDB's fork, 4.x line)   | `com.scylladb:java-driver-core:4.19.2.0` (Maven). Requires Java 11+ (Java 8 support was dropped as of this release). |
| Go       | gocql + gocqlx                            | `go get github.com/scylladb/gocql`                 |
| Rust     | scylla-rust-driver                        | `cargo add scylla`                                 |
| C#       | scylla-csharp-driver                      | NuGet package                                      |
| C++      | cpp-rust-driver                           | Build from source or vcpkg                         |
| Node.js  | scylla-node-driver                        | `npm install @scylladb/driver`                     |

⚠️ **Important**: ScyllaDB has its own driver forks — do **not** use the DataStax/Cassandra drivers - unless there's no ScyllaDB driver available for your language. ScyllaDB drivers include shard-aware optimizations that route requests directly to the correct CPU core, improving throughput and latency.

## Step 4: Configure the Connection

Consult `references/driver-configuration.md` for per-language connection snippets.

**Critical requirements for ScyllaDB Cloud:**

**Authentication** — `PlainTextAuthProvider` with the username and password from Step 2.

Consult `references/cloud-connection.md` for details on IP allowlisting and VPC peering.

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
5. **Using Cassandra driver instead of ScyllaDB driver** — the DataStax drivers lack shard-aware routing and may have compatibility issues

## Step 6: Next Steps

Once connected, suggest relevant next steps:

- **Data modeling**: Use the `scylladb-data-modeling` skill for schema design guidance
- **Vector search**: Use the `scylladb-vector-search` skill if they need similarity search
- **Prepared statements**: Recommend using prepared statements for all frequently-run queries (reduces parsing overhead, enables token-aware routing). See `references/prepared-statements.md` for the full pattern with examples.
- **Connection pooling**: ScyllaDB drivers handle pooling internally with shard-aware connections — typically no manual tuning needed
- **Infrastructure as code**: If the user wants to manage cluster provisioning declaratively (not just connect an app to an existing cluster), point them to the [ScyllaDB Cloud Terraform provider](https://registry.terraform.io/providers/scylladb/scylladbcloud/latest/docs) rather than only the manual Console flow in Step 1.
- **ScyllaDB Cloud MCP server**: If the user wants to manage their ScyllaDB Cloud cluster programmatically via an AI agent (create clusters, monitor health, configure networking, etc.), the ScyllaDB Cloud MCP server is available. See the full documentation at <https://cloud.docs.scylladb.com/master/api-docs/mcp>
