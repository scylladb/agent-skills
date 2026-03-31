---
title: "Driver Integration for Vector Search"
tags: vector-search, drivers, Python, Java, Go, Rust, DC-aware, shard-aware
---

# Driver Integration for Vector Search

## Requirements

1. **Driver must support the `vector` CQL type** — see minimum versions below
2. **DC-aware load balancing policy is required** — vector search will not work without it

## Driver Version Requirements

| Driver | Minimum Version for Vector Search | Recommended |
|--------|----------------------------------|-------------|
| Python (`scylla-driver`) | 3.28.0 | Latest |
| Java (`java-driver` 4.x) | 4.16.0 | 4.19.0+ |
| Java (`java-driver` 3.x) | Not supported | Upgrade to 4.x |
| Go (`gocql`) | 1.17.0 | Latest |
| Go (`gocqlx`) | Not yet supported | Use `gocql` directly |
| Rust (`scylla`) | 1.2.0 | Latest |
| C# (`scylla-csharp-driver`) | All versions | Latest |
| CPP RS (`cpp-rust-driver`) | 0.5.1 | Latest |
| Node.js RS (`scylla-node-driver`) | All versions | Latest |

## Connection Examples

All examples connect to ScyllaDB Cloud with TLS and DC-aware load balancing.

### Python

```python
import ssl
from cassandra.cluster import Cluster
from cassandra.auth import PlainTextAuthProvider
from cassandra.policies import DCAwareRoundRobinPolicy

auth = PlainTextAuthProvider(username='scylla', password='YOUR_PASSWORD')
ssl_context = ssl.create_default_context()
cluster = Cluster(
    contact_points=['node-0.your-cluster.cloud.scylladb.com'],
    port=9042,
    auth_provider=auth,
    load_balancing_policy=DCAwareRoundRobinPolicy(local_dc='AWS_US_EAST_1'),
    ssl_context=ssl_context,
)
session = cluster.connect('myapp')

# Insert a vector
session.execute(
    """INSERT INTO documents (doc_id, title, content, embedding, created_at)
       VALUES (now(), %s, %s, %s, toTimestamp(now()))""",
    ('My Title', 'My content...', [0.12, 0.34, 0.56, 0.78, 0.91])
)

# Run a similarity search
query_vec = [0.12, 0.34, 0.56, 0.78, 0.91]
rows = session.execute(
    """SELECT doc_id, title,
              similarity_cosine(embedding, %s) AS score
       FROM documents
       ORDER BY embedding ANN OF %s LIMIT 5""",
    (query_vec, query_vec)
)
for row in rows:
    print(f"{row.title}: {row.score:.4f}")
```

### Node.js (RS Driver)

Refer to the [Node.js RS Driver documentation](https://docs.scylladb.com/stable/drivers/cql-drivers.html) for vector type examples. Built on a Rust core with full shard-aware routing.

### Java (4.x)

```java
import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.cql.*;
import java.util.*;

// Assumes session is already connected with DC-aware policy

// Insert a vector
List<Float> embedding = Arrays.asList(0.12f, 0.34f, 0.56f, 0.78f, 0.91f);
session.execute(
    SimpleStatement.newInstance(
        "INSERT INTO myapp.documents (doc_id, title, embedding) VALUES (uuid(), ?, ?)",
        "My Title", embedding
    )
);

// Run a similarity search
List<Float> queryVec = Arrays.asList(0.12f, 0.34f, 0.56f, 0.78f, 0.91f);
ResultSet rs = session.execute(
    SimpleStatement.newInstance(
        "SELECT doc_id, title FROM myapp.documents ORDER BY embedding ANN OF ? LIMIT 5",
        queryVec
    )
);
```

### Go

```go
// Assumes session is already connected with DC-aware policy

queryVec := []float32{0.12, 0.34, 0.56, 0.78, 0.91}
iter := session.Query(
    "SELECT doc_id, title FROM myapp.documents ORDER BY embedding ANN OF ? LIMIT 5",
    queryVec,
).Iter()

var docID gocql.UUID
var title string
for iter.Scan(&docID, &title) {
    fmt.Printf("%s: %s\n", docID, title)
}
```

## Using Prepared Statements

Always use prepared statements for production vector queries to enable token-aware routing and reduce parsing overhead:

```python
# Python example with prepared statement
insert_stmt = session.prepare(
    """INSERT INTO documents (doc_id, title, content, embedding, created_at)
       VALUES (?, ?, ?, ?, toTimestamp(now()))"""
)
session.execute(insert_stmt, [uuid4(), 'My Title', 'My content...', query_vec])

search_stmt = session.prepare(
    """SELECT doc_id, title, similarity_cosine(embedding, ?) AS score
       FROM documents
       ORDER BY embedding ANN OF ? LIMIT ?"""
)
rows = session.execute(search_stmt, [query_vec, query_vec, 10])
```
