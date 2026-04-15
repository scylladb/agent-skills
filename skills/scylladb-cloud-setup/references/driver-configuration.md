---
title: ScyllaDB Driver Configuration
tags: drivers, Python, Java, Go, Rust, C#, Node.js, connection, shard-aware, DC-aware
---

# ScyllaDB Driver Configuration

All examples connect to a ScyllaDB Cloud cluster with:
- DC-aware load balancing policy (required)
- `PlainTextAuthProvider` for authentication

⚠️ **Use ScyllaDB drivers, not DataStax/Cassandra drivers.** ScyllaDB drivers include shard-aware routing that sends each query directly to the correct CPU core, dramatically improving throughput and reducing latency.

---

## Python (`scylla-driver`)

```bash
pip install scylla-driver
```

```python
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.policies import DCAwareRoundRobinPolicy

auth = PlainTextAuthProvider(username='scylla', password='YOUR_PASSWORD')

cluster = Cluster(
    contact_points=['node-0.your-cluster.cloud.scylladb.com'],
    port=9042,
    auth_provider=auth,
    load_balancing_policy=DCAwareRoundRobinPolicy(local_dc='AWS_US_EAST_1'),
)
session = cluster.connect()

row = session.execute("SELECT release_version FROM system.local").one()
print(f"Connected to ScyllaDB {row.release_version}")
```

**Minimum version for vector search**: 3.28.0
**Minimum version for tablets**: 3.26.5

---

## Java (`java-driver` 4.x)

Maven dependency:
```xml
<dependency>
    <groupId>com.scylladb</groupId>
    <artifactId>java-driver-core</artifactId>
    <version>4.19.0</version>
</dependency>
```

```java
import com.datastax.oss.driver.api.core.CqlSession;
import java.net.InetSocketAddress;

CqlSession session = CqlSession.builder()
    .addContactPoint(new InetSocketAddress("node-0.your-cluster.cloud.scylladb.com", 9042))
    .withLocalDatacenter("AWS_US_EAST_1")
    .withAuthCredentials("scylla", "YOUR_PASSWORD")
    .build();

session.execute("SELECT release_version FROM system.local")
    .one()
    .getString("release_version");
```

**Minimum version for vector search**: 4.16.0 (recommended 4.19.0+)
**Minimum version for tablets**: 4.18.0

---

## Go (`gocql`)

```bash
go get github.com/scylladb/gocql
```

```go
package main

import (
    "fmt"
    "log"

    "github.com/scylladb/gocql"
)

func main() {
    cluster := gocql.NewCluster("node-0.your-cluster.cloud.scylladb.com")
    cluster.Port = 9042
    cluster.Authenticator = gocql.PasswordAuthenticator{
        Username: "scylla",
        Password: "YOUR_PASSWORD",
    }
    cluster.PoolConfig.HostSelectionPolicy = gocql.DCAwareRoundRobinPolicy("AWS_US_EAST_1")

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

---

## Rust (`scylla`)

```toml
[dependencies]
scylla = "1.2"
tokio = { version = "1", features = ["full"] }
```

```rust
use scylla::{SessionBuilder, transport::Compression};
use std::error::Error;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let session = SessionBuilder::new()
        .known_node("node-0.your-cluster.cloud.scylladb.com:9042")
        .user("scylla", "YOUR_PASSWORD")
        .build()
        .await?;

    let result = session
        .query_unpaged("SELECT release_version FROM system.local", &[])
        .await?;
    println!("Connected to ScyllaDB");
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
    .Build();

var session = cluster.Connect();
var row = session.Execute("SELECT release_version FROM system.local").First();
Console.WriteLine($"Connected to ScyllaDB {row.GetValue<string>("release_version")}");
```

**Vector search support**: All versions
**Tablets support**: All versions

---

## Node.js RS (`scylla-node-driver`)

```bash
npm install @aspect-build/scylla-driver
```

Refer to the [Node.js RS Driver documentation](https://docs.scylladb.com/stable/drivers/cql-drivers.html) for connection examples. The Node.js RS driver is built on a Rust core and provides shard-aware, fully asynchronous connections.

**Vector search support**: All versions
**Tablets support**: All versions

---

## CPP RS (`cpp-rust-driver`)

Refer to the [CPP RS Driver documentation](https://docs.scylladb.com/stable/drivers/cql-drivers.html) for connection examples. Built on a Rust core for memory safety with C++ usability.

**Vector search support**: 0.5.1+
**Tablets support**: All versions

---

## Key Configuration Notes

### DC-Aware Load Balancing (Required)
Every ScyllaDB Cloud connection **must** use a DC-aware load balancing policy set to the cluster's datacenter name. Without it:
- Queries may be routed to the wrong datacenter
- Connection may fail entirely
- Latency will be unpredictable

### Shard-Aware Routing
ScyllaDB drivers automatically detect the shard-per-core architecture and route queries directly to the correct shard. This is transparent — no configuration needed beyond using the ScyllaDB driver (not the Cassandra driver).

### Prepared Statements
Always use prepared statements for repeated queries. Benefits:
- Reduced parsing overhead on the server
- Enables token-aware routing (queries go to the correct node/shard based on partition key)
- Type safety for bound parameters

### Connection Pooling
ScyllaDB drivers manage connections internally with shard-aware pools.