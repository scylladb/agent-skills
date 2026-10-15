# Local Vector Search with Docker

Run Vector Search on a laptop or in CI for development and tests. This setup is **not for production**: ScyllaDB supports Vector Search only on ScyllaDB Cloud, not on self-hosted or on-prem deployments.

## How It Fits Together

Vector Search needs two services, not one:

| Container | Image | Role |
| --- | --- | --- |
| ScyllaDB | `scylladb/scylla` | Stores the table, accepts CQL, forwards ANN queries |
| Vector Store | `scylladb/vector-store` | Builds and serves the HNSW index; reads changes from ScyllaDB through CDC |

A `scylladb/scylla` container alone is not enough: without a connected Vector Store, vector indexes and ANN queries do not work.

## Start the Stack

Use the Docker Compose file maintained in the Vector Store repo. It pins a ScyllaDB version that works with the current Vector Store release:

```sh
curl -sLO https://raw.githubusercontent.com/scylladb/vector-store/master/docs/examples/docker/docker-compose.yml
docker compose up -d
```

CQL is on `localhost:9042`. Connect with no credentials and local DC `datacenter1`.

## Wiring a Custom Setup

When the user builds their own setup (Testcontainers, a different compose file, CI scripts), the two containers must reach each other by hostname on a shared Docker network. Set these:

- ScyllaDB command-line flag: `--vector-store-primary-uri http://<vector-store-host>:6080` (config key `vector_store_primary_uri`, see the [configuration reference](https://docs.scylladb.com/manual/stable/reference/configuration-parameters.md)).
- Vector Store environment variables: `VECTOR_STORE_URI=0.0.0.0:6080` (the default `127.0.0.1:6080` is unreachable from the ScyllaDB container) and `VECTOR_STORE_SCYLLADB_URI=<scylla-host>:9042`. All variables are listed in the [Vector Store README](https://github.com/scylladb/vector-store#configuration).
- Start the Vector Store only after ScyllaDB accepts CQL connections (log line `Starting listening for CQL clients`, or a `cqlsh` health check).
- For low memory use, run ScyllaDB with `--smp 1 --memory 1G --overprovisioned 1`.
- Use current image tags. Check [scylladb/scylla](https://hub.docker.com/r/scylladb/scylla/tags) and [scylladb/vector-store](https://hub.docker.com/r/scylladb/vector-store/tags) on Docker Hub, and do not copy old versions from blog posts or gists.

## Keyspace for a Single Node

A single node needs replication factor 1:

```cql
CREATE KEYSPACE IF NOT EXISTS myapp
WITH replication = {'class': 'NetworkTopologyStrategy', 'replication_factor': 1};
```

Tablets are enabled by default, which Vector Search requires (see [vector-type-and-indexing](vector-type-and-indexing.md)). Then follow the normal workflow: create the table, create the vector index, insert vectors, run ANN queries.

## Limitations

- Not for production. Single node, RF=1, no authentication or TLS, and one Vector Store with no failover.
- The index lives in the Vector Store container's memory. After a restart, the Vector Store rebuilds it from the table before it serves queries again.
- Performance numbers from a local setup do not predict ScyllaDB Cloud performance.
