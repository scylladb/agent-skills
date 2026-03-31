---
title: "ANN Queries"
tags: vector-search, ANN, ORDER BY, LIMIT, similarity-functions, query-syntax
---

# ANN Queries

## Syntax

```sql
SELECT column1, column2, ...
FROM keyspace.table
ORDER BY vector_column ANN OF [v1, v2, ..., vn]
LIMIT k;
```

- `vector_column` — the indexed vector column
- `[v1, ..., vn]` — the query vector (must match the column's dimensionality)
- `k` — number of nearest neighbors to return (**required** — ScyllaDB rejects queries without `LIMIT`)

## Basic Example

```sql
SELECT doc_id, title, content
FROM myapp.documents
ORDER BY embedding ANN OF [0.12, 0.34, 0.56, 0.78, ...]
LIMIT 10;
```

Returns the 10 documents whose embeddings are most similar to the query vector, ranked by the similarity function defined in the index.

## Retrieving Similarity Scores

Use the similarity function matching your index configuration:

```sql
SELECT doc_id, title,
       similarity_cosine(embedding, [0.12, 0.34, ...]) AS score
FROM myapp.documents
ORDER BY embedding ANN OF [0.12, 0.34, ...]
LIMIT 10;
```

**Available functions:**
- `similarity_cosine(col, vec)` — use with `COSINE` indexes
- `similarity_dot_product(col, vec)` — use with `DOT_PRODUCT` indexes
- `similarity_euclidean(col, vec)` — use with `EUCLIDEAN` indexes

All return a `float` in `[0, 1]` where values closer to 1 indicate greater similarity.

## Write-to-Query Latency

After inserting or updating a vector, there is a short delay before it appears in ANN query results:

- **Typical p50 latency**: under 1 second (sub-second fine-grained CDC reader)
- **Consistency guarantee**: 30-second safety interval (wide-framed CDC reader catches any missed data)

For most workloads, newly inserted vectors are queryable within approximately 1 second. If a just-inserted vector doesn't appear in results, wait 1-2 seconds and retry.

## Query Behavior

- `LIMIT` limits the number of results **after** any filtering (not before)
- ANN is approximate — results are "sufficiently similar" but not guaranteed to be the exact nearest neighbors
- Increasing `search_beam_width` (index parameter) improves recall at the cost of latency
- Without a vector index, the query would require a brute-force scan of all vectors (not scalable)

## Common Patterns

### Similarity Threshold (Application-Side)

ScyllaDB does not support a minimum similarity threshold in CQL. Filter in your application:

```python
rows = session.execute(
    """SELECT doc_id, title,
              similarity_cosine(embedding, %s) AS score
       FROM myapp.documents
       ORDER BY embedding ANN OF %s LIMIT 20""",
    (query_vec, query_vec)
)
# Filter to only results above threshold
results = [row for row in rows if row.score >= 0.7]
```

### Pagination

ANN queries do not support CQL paging (no `OFFSET`). For pagination:
1. Use a larger `LIMIT` and paginate application-side
2. Or use the similarity score from the last result as a filter threshold

### Combining with Non-Vector Columns

You can select any column in the table alongside the ANN query:

```sql
SELECT doc_id, title, content, created_at,
       similarity_cosine(embedding, [...]) AS score
FROM myapp.documents
ORDER BY embedding ANN OF [...]
LIMIT 10;
```

## CQL Features NOT Supported

- `DISTINCT` keyword in ANN queries
- `TOKEN` function in vector queries
- `CONTAINS` operator in vector queries
- Filtering on columns not in the primary key (see `filtering.md` for supported filtering)
- `ALTER INDEX` (must drop and recreate to change index options)
- TTL on columns with a vector index
