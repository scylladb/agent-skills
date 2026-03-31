---
title: "Filtering Vector Search Results"
tags: vector-search, filtering, global-index, local-index, partition-key, WHERE
---

# Filtering Vector Search Results

Filtering combines similarity search with metadata constraints so results are both semantically relevant and meet business requirements (multi-tenant isolation, recency, access control, etc.).

## Two Index Types

| | Global Vector Index | Local Vector Index |
|---|---|---|
| **Scope** | All rows in the table | Rows within a single partition |
| **Filter columns** | Primary key columns | Primary key columns |
| **Requires partition key in WHERE** | No | Yes (full partition key required) |
| **Performance** | Always much slower (searches entire index space) | Fast (searches only one partition's index) |
| **ALLOW FILTERING required** | Yes (when using WHERE) | No |
| **Use case** | Cross-partition search | Per-tenant, per-user, scoped search |

**Always prefer local indexes over global indexes for filtered vector search.**

## Global Vector Index

### Creation

```sql
CREATE CUSTOM INDEX IF NOT EXISTS global_ann_idx
ON myapp.comments(comment_vector)
USING 'vector_index'
WITH OPTIONS = { 'similarity_function': 'DOT_PRODUCT' };
```

Same syntax as a standard vector index. Filters on any column in the base table's primary key.

### Querying

```sql
SELECT commenter, comment FROM myapp.comments
WHERE created_at = '2024-01-01'
ORDER BY comment_vector ANN OF [0.1, 0.2, 0.3, 0.4, 0.5] LIMIT 5
ALLOW FILTERING;
```

⚠️ Global index queries are **always** slower than local index queries because ScyllaDB must search the entire index space across all partitions and then post-filter. The more selective the filter, the slower the query (more index entries scanned to find matches).

## Local Vector Index

### Example Schema

```sql
CREATE TABLE IF NOT EXISTS myapp.comments (
    commenter text,
    discussion_board_id int,
    comment text,
    comment_vector vector<float, 5>,
    created_at timestamp,
    PRIMARY KEY ((commenter, discussion_board_id), created_at)
);
```

### Creation

The local index specifies the partition key columns in parentheses before the vector column:

```sql
CREATE CUSTOM INDEX IF NOT EXISTS local_ann_idx
ON myapp.comments((commenter, discussion_board_id), comment_vector)
USING 'vector_index'
WITH OPTIONS = { 'similarity_function': 'DOT_PRODUCT' };
```

- `(commenter, discussion_board_id)` — must match the base table's partition key
- `comment_vector` — the vector column to index

For each unique partition key value, ScyllaDB maintains a **separate** vector index — small and fast to search.

### Querying

You **must** specify the full partition key in the `WHERE` clause:

```sql
-- Find similar comments by Alice in discussion board 42
SELECT commenter, comment FROM myapp.comments
WHERE commenter = 'Alice' AND discussion_board_id = 42
ORDER BY comment_vector ANN OF [0.1, 0.2, 0.3, 0.4, 0.5] LIMIT 5;
```

Can combine with clustering column filters:

```sql
SELECT commenter, comment FROM myapp.comments
WHERE commenter = 'Alice' AND discussion_board_id = 42
  AND created_at >= '2024-01-01'
ORDER BY comment_vector ANN OF [0.1, 0.2, 0.3, 0.4, 0.5] LIMIT 5;
```

## Schema Design for Filtering

**Best practice**: Design your schema so that the columns you filter on are part of the partition key, then use a local vector index.

### Multi-Tenant Example

```sql
CREATE TABLE myapp.tenant_documents (
    tenant_id uuid,
    doc_id uuid,
    content text,
    embedding vector<float, 768>,
    created_at timestamp,
    PRIMARY KEY (tenant_id, created_at, doc_id)
);

CREATE CUSTOM INDEX ON myapp.tenant_documents((tenant_id), embedding)
USING 'vector_index'
WITH OPTIONS = { 'similarity_function': 'COSINE' };

-- Query: find similar documents within a specific tenant
SELECT doc_id, content FROM myapp.tenant_documents
WHERE tenant_id = ?
ORDER BY embedding ANN OF [...] LIMIT 10;
```

## Performance Guidelines

- **Equality filters on partition key columns** = fastest path (local index)
- **Inequality operators** (`>`, `<`, `>=`, `<=`, `IN`) are always slow regardless of index type — they force scanning a larger portion of the index
- If both a global and local index exist on the same vector column, ScyllaDB automatically selects the local index when the partition key is specified

## Limitations

- Filtering on columns **not** in the primary key is not supported
- `TOKEN`, `CONTAINS`, and `DISTINCT` are not supported in vector queries
- Only one local vector index per combination of partition key columns and vector column
