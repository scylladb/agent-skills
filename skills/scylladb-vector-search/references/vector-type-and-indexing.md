---
title: "Vector Data Type and Indexing"
tags: vector-search, vector-type, HNSW, index, similarity, CREATE CUSTOM INDEX
---

# Vector Data Type and Indexing

## Vector Data Type

The `VECTOR` data type stores fixed-length numeric vectors as a native CQL column type.

**Syntax**: `vector<element_type, dimension>` (e.g., `vector<float, 768>`)

- **Element types**: `float` (most common)
- **Dimensions**: 1 to 16,000
- **Protocol**: Requires CQL native protocol v5 (supported by all current ScyllaDB drivers)

### Tablets Requirement

⚠️ **Tables with vector columns MUST reside in a keyspace with tablets enabled.** ScyllaDB Cloud enables tablets by default in all new keyspaces. For older clusters, explicitly enable tablets:

```sql
CREATE KEYSPACE myapp
WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'replication_factor': 3
}
AND tablets = {
   'enabled': true
};
```

### Creating a Table with a Vector Column

```sql
CREATE TABLE IF NOT EXISTS myapp.documents (
    doc_id uuid,
    title text,
    content text,
    embedding vector<float, 768>,
    created_at timestamp,
    PRIMARY KEY (doc_id)
);
```

**Note**: The example above uses 768 dimensions matching `all-MiniLM-L6-v2`. In production, set dimensions to match your embedding model's output exactly.

## Vector Index

The vector index uses the HNSW (Hierarchical Navigable Small World) algorithm for Approximate Nearest Neighbor (ANN) search.

### Creating a Vector Index

```sql
CREATE CUSTOM INDEX IF NOT EXISTS doc_embedding_idx
ON myapp.documents(embedding)
USING 'vector_index'
WITH OPTIONS = { 'similarity_function': 'COSINE' };
```

### Similarity Functions

| Function | When to Use | Notes |
|----------|------------|-------|
| `COSINE` (default) | Most text embedding models (OpenAI, sentence-transformers) | Measures angle between vectors. Use when magnitude is irrelevant |
| `DOT_PRODUCT` | Non-normalized embeddings, or when magnitude carries meaning | Slightly faster than cosine. Requires careful handling of varying magnitudes |
| `EUCLIDEAN` | Spatial data, geographic coordinates | Measures straight-line distance. Less common for text embeddings |

**Decision process:**
1. Check your embedding model documentation for the recommended function
2. If model outputs normalized vectors → `DOT_PRODUCT` (fastest) or `COSINE`
3. If model does NOT normalize → `COSINE`
4. For spatial data → `EUCLIDEAN`
5. When uncertain → `COSINE` (safe default)

### HNSW Tuning Parameters

| Parameter | Default | Range | Effect |
|-----------|---------|-------|--------|
| `maximum_node_connections` (m) | 16 | — | Max connections per node in HNSW graph. Higher → better recall, more memory, slower builds |
| `construction_beam_width` (ef_construct) | 128 | — | Candidates evaluated during build. Higher → better graph quality, slower builds |
| `search_beam_width` (ef_search) | 128 | — | Candidates evaluated during query. Higher → better recall, higher query latency |

```sql
CREATE CUSTOM INDEX IF NOT EXISTS tuned_idx
ON myapp.documents(embedding)
USING 'vector_index'
WITH OPTIONS = {
  'similarity_function': 'COSINE',
  'maximum_node_connections': '32',
  'construction_beam_width': '200',
  'search_beam_width': '200'
};
```

**Guidance:**
- Start with defaults
- Increase `search_beam_width` first if recall is too low
- Increase `maximum_node_connections` for high-dimensional vectors (>512 dimensions)
- **Index options cannot be altered after creation** — you must drop and recreate the index to change parameters

### Inserting Vectors

```sql
INSERT INTO myapp.documents (doc_id, title, content, embedding, created_at)
VALUES (
    uuid(), 'Introduction to ScyllaDB',
    'ScyllaDB is a high-performance NoSQL database...',
    [0.12, 0.34, 0.56, ...],  -- 768 floats from your embedding model
    toTimestamp(now())
);
```

- The vector must match the dimension and element type declared in the schema
- Values are enclosed in square brackets `[...]`
- Use the same embedding model for all vectors in a column

### Unsupported Features with Vector Indexes

- `ALTER INDEX` — cannot modify index options after creation; drop and recreate instead
- TTL — creating a vector index on a table with `default_time_to_live` is rejected
- Writes with TTL on a column with a vector index are ignored
- `DISTINCT`, `TOKEN`, `CONTAINS` operators are not supported in vector queries
