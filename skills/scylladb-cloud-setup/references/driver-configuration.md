---
title: ScyllaDB Driver Configuration
tags: drivers, Python, Java, Go, Rust, C#, javascript, Node.js, connection, shard-aware, tablet-aware, DC-aware, consistency
---

# ScyllaDB Driver Configuration

All examples connect to a ScyllaDB Cloud cluster with:
- Token-aware, DC-aware load balancing policy (recommended)
- `PlainTextAuthProvider` for authentication
- `LOCAL_QUORUM` as the default consistency level

Contents: Python, Java, Go, Rust, C#, Node.js, CPP RS, then key configuration notes (routing, prepared statements, connection pooling).

⚠️ **Use ScyllaDB drivers, not DataStax/Cassandra drivers.** ScyllaDB drivers include shard-aware and tablet-aware routing that sends each query directly to the correct node and CPU core.

---

## Python (`scylla-driver`)

```bash
pip install scylla-driver
```

```python
from cassandra import ConsistencyLevel
from cassandra.auth import PlainTextAuthProvider
from cassandra.cluster import Cluster, ExecutionProfile, EXEC_PROFILE_DEFAULT
from cassandra.policies import DCAwareRoundRobinPolicy, TokenAwarePolicy

auth = PlainTextAuthProvider(username='scylla', password='YOUR_PASSWORD')

profile = ExecutionProfile(
    load_balancing_policy=TokenAwarePolicy(DCAwareRoundRobinPolicy(local_dc='AWS_US_EAST_1')),
    consistency_level=ConsistencyLevel.LOCAL_QUORUM,
)

cluster = Cluster(
    contact_points=['node-0.your-cluster.cloud.scylladb.com'],
    port=9042,
    auth_provider=auth,
    execution_profiles={EXEC_PROFILE_DEFAULT: profile},
)
session = cluster.connect()

row = session.execute("SELECT release_version FROM system.local").one()
print(f"Connected to ScyllaDB {row.release_version}")
```

Do not mix `ExecutionProfile` with the legacy `Cluster(load_balancing_policy=...)` argument or `session.default_consistency_level`. The driver does not allow [both APIs on one `Cluster`](https://python-driver.docs.scylladb.com/stable/execution-profiles.md).

**Minimum version for vector search**: 3.28.0
**Minimum version for tablets**: 3.26.5

---

## Java (`java-driver` 4.x)

Maven dependency:
```xml
<dependency>
    <groupId>com.scylladb</groupId>
    <artifactId>java-driver-core</artifactId>
    <version>4.19.2.2</version>
</dependency>
```

```java
import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.config.DefaultDriverOption;
import com.datastax.oss.driver.api.core.config.DriverConfigLoader;
import java.net.InetSocketAddress;

CqlSession session = CqlSession.builder()
    .addContactPoint(new InetSocketAddress("node-0.your-cluster.cloud.scylladb.com", 9042))
    .withLocalDatacenter("AWS_US_EAST_1")
    .withAuthCredentials("scylla", "YOUR_PASSWORD")
    .withConfigLoader(DriverConfigLoader.programmaticBuilder()
        .withString(DefaultDriverOption.REQUEST_CONSISTENCY, "LOCAL_QUORUM")
        .build())
    .build();

session.execute("SELECT release_version FROM system.local")
    .one()
    .getString("release_version");
```

**Minimum version for vector search**: 4.16.0 (recommended: the latest 4.x release)
**Minimum version for tablets**: 4.18.0

The Java 4.x default load balancing policy is token-aware. To set consistency in `application.conf` instead of code, use `datastax-java-driver.basic.request.consistency = LOCAL_QUORUM` ([configuration](https://java-driver.docs.scylladb.com/stable/manual/core/configuration/index.md)).

---

## Go (`gocql`)

The ScyllaDB fork keeps the `github.com/gocql/gocql` module path. Install it with a `replace` directive ([quick start](https://gocql-driver.docs.scylladb.com/stable/quick-start.md)). `go get github.com/scylladb/gocql` fails because of the module path.

```bash
go mod edit -replace=github.com/gocql/gocql=github.com/scylladb/gocql@v1.20.0
go get github.com/gocql/gocql
```

```go
package main

import (
    "fmt"
    "log"

    "github.com/gocql/gocql"
)

func main() {
    cluster := gocql.NewCluster("node-0.your-cluster.cloud.scylladb.com")
    cluster.Port = 9042
    cluster.Authenticator = gocql.PasswordAuthenticator{
        Username: "scylla",
        Password: "YOUR_PASSWORD",
    }
    cluster.PoolConfig.HostSelectionPolicy = gocql.TokenAwareHostPolicy(
        gocql.DCAwareRoundRobinPolicy("AWS_US_EAST_1"),
    )
    cluster.Consistency = gocql.LocalQuorum

    session, err := cluster.CreateSession()
    if err != nil {
        log.Fatal(err)
    }
    defer session.Close()

    var version string
    if err := session.Query("SELECT release_version FROM system.local").Scan(&version); err != nil {
        log.Fatal(err)
    }
    fmt.Printf("Connected to ScyllaDB %s\n", version)
}
```

**Minimum version for vector search**: 1.17.0
**Minimum version for tablets**: 1.13.0

`gocqlx` (`github.com/scylladb/gocqlx/v3`) is an optional wrapper for struct binding and query building. It needs the same `replace` directive. The [driver docs](https://docs.scylladb.com/stable/drivers/cql-drivers.md) mark it as not supported for tablets and the `vector` type. `gocqlx` sends queries through the wrapped gocql session, so the gocql version that the `replace` directive selects controls routing. For `vector` columns, use gocql directly.

---

## Rust (`scylla`)

```toml
[dependencies]
scylla = "1.2"
tokio = { version = "1", features = ["full"] }
```

```rust
use scylla::client::execution_profile::ExecutionProfile;
use scylla::client::session::Session;
use scylla::client::session_builder::SessionBuilder;
use scylla::policies::load_balancing::DefaultPolicy;
use scylla::statement::Consistency;
use std::error::Error;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let policy = DefaultPolicy::builder()
        .prefer_datacenter("AWS_US_EAST_1".to_string())
        .token_aware(true)
        .permit_dc_failover(false)
        .build();
    let profile = ExecutionProfile::builder()
        .load_balancing_policy(policy)
        .consistency(Consistency::LocalQuorum)
        .build();

    let session: Session = SessionBuilder::new()
        .known_node("node-0.your-cluster.cloud.scylladb.com:9042")
        .user("scylla", "YOUR_PASSWORD")
        .default_execution_profile_handle(profile.into_handle())
        .build()
        .await?;

    let (version,) = session
        .query_unpaged("SELECT release_version FROM system.local", &[])
        .await?
        .into_rows_result()?
        .single_row::<(String,)>()?;
    println!("Connected to ScyllaDB {version}");
    Ok(())
}
```

**Minimum version for vector search**: 1.2.0
**Minimum version for tablets**: 0.13.0

---

## C# (`scylla-csharp-driver`)

```bash
dotnet add package ScyllaDB.CSharpDriver
```

```csharp
using Cassandra;

var cluster = Cluster.Builder()
    .AddContactPoint("node-0.your-cluster.cloud.scylladb.com")
    .WithPort(9042)
    .WithCredentials("scylla", "YOUR_PASSWORD")
    .WithLoadBalancingPolicy(new TokenAwarePolicy(
        new DCAwareRoundRobinPolicy("AWS_US_EAST_1")))
    .WithQueryOptions(new QueryOptions()
        .SetConsistencyLevel(ConsistencyLevel.LocalQuorum))
    .Build();

var session = cluster.Connect();
var row = session.Execute("SELECT release_version FROM system.local").First();
Console.WriteLine($"Connected to ScyllaDB {row.GetValue<string>("release_version")}");
```

**Vector search support**: All versions
**Tablets support**: All versions

---

## Javascript (`@scylladb/driver`)
A client-side driver for ScyllaDB written in Node.js and Rust. 

```bash
npm install @scylladb/driver
```

Get started: https://nodejs-rs-driver.docs.scylladb.com/stable/getting-started/getting-started.md
Best practices: https://nodejs-rs-driver.docs.scylladb.com/stable/statements/prepared.md

Set the default consistency in the `Client` options: `queryOptions: { consistency: types.consistencies.localQuorum }`, with `types` imported from `@scylladb/driver`.

**Vector search support**: All versions
**Tablets support**: All versions

---

## CPP RS (`cpp-rust-driver`)

Refer to the [CPP RS Driver documentation](https://docs.scylladb.com/stable/drivers/cql-drivers.md) for connection examples. Built on a Rust core for memory safety with C++ usability.

**Vector search support**: 0.5.1+
**Tablets support**: All versions

---

## Key Configuration Notes

### Shard-Aware and Tablet-Aware Routing
ScyllaDB drivers detect the shard-per-core architecture and route queries directly to the correct shard. For tablet tables, the server sends tablet replica information to the driver when a request goes to the wrong node or shard, and the driver uses it for later requests ([protocol extension](https://github.com/scylladb/scylladb/blob/master/docs/dev/protocol-extensions.md#tablets-routing-v1)). Both need a token-aware load balancing policy and prepared statements. Tablet awareness also needs the minimum driver version listed for each driver above.

### Prepared Statements
Always use prepared statements for repeated queries. Benefits:
- Reduced parsing overhead on the server
- Enables token-aware routing (queries go to the correct node/shard based on partition key)
- Type safety for bound parameters

### Connection Pooling
A shard-aware driver opens one connection per shard on each node, so each client session opens (nodes × shards per node) connections. This is expected. Do not reduce the pool size to lower it. gocql ignores `ClusterConfig.NumConns` when the cluster is shard-aware ([load balancing](https://gocql-driver.docs.scylladb.com/stable/load-balancing.md)). The Rust driver recommends its default, `PoolSize::PerShard(1)` ([`PoolSize`](https://docs.rs/scylla/latest/scylla/client/enum.PoolSize.html)).

The count becomes a problem when many client processes on one host each create their own session, for example pre-fork web server workers. Each process opens the full set. First, make sure each process creates only one session. If the count is still too high, disable shard awareness to get one connection per host. In Python, use `Cluster(shard_aware_options=dict(disable=True))` ([ScyllaDB-specific features](https://python-driver.docs.scylladb.com/stable/scylla-specific.md)). Requests then reach each node on one connection, and the node forwards them to the shard that owns the data.
