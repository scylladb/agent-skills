---
title: "Hybrid Search"
tags: hybrid-search, BM25, ANN, reciprocal-rank-fusion, RRF
---

# Hybrid Search

Hybrid search combines full-text (BM25) and vector (ANN) results for one query. As of ScyllaDB 2026.3 there is no native hybrid query: `BM25()` and `ANN OF` cannot be in the same statement. Run two queries and merge the results in the application ([Combining Full Text and Vector Search](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-hybrid)).

## Schema

Put a full-text index and a vector index on the same table:

```cql
CREATE TABLE IF NOT EXISTS myapp.docs (
  id int PRIMARY KEY,
  body text,
  embedding vector<float, 384>
);

CREATE CUSTOM INDEX IF NOT EXISTS docs_body_fts ON myapp.docs(body) USING 'fulltext_index';
CREATE CUSTOM INDEX IF NOT EXISTS docs_embedding_ann ON myapp.docs(embedding) USING 'vector_index';
```

## Merge With Reciprocal Rank Fusion

BM25 scores are not returned, and they are not comparable with similarity scores. Merge by rank with Reciprocal Rank Fusion (RRF). Python, with an open `session`:

```python
bm25 = session.prepare(
    "SELECT id FROM myapp.docs WHERE BM25(body, ?) > 0 ORDER BY BM25(body, ?) LIMIT ?"
)
ann = session.prepare("SELECT id FROM myapp.docs ORDER BY embedding ANN OF ? LIMIT ?")


def rrf(*ranked_lists, k=60):
    """Merge ranked lists of primary keys with Reciprocal Rank Fusion."""
    scores = {}
    for ranked in ranked_lists:
        for rank, key in enumerate(ranked, start=1):
            scores[key] = scores.get(key, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=scores.get, reverse=True)


def hybrid_search(query_text, query_vector, limit=10):
    keyword = [row.id for row in session.execute(bm25, (query_text, query_text, limit))]
    semantic = [row.id for row in session.execute(ann, (query_vector, limit))]
    return rrf(keyword, semantic)[:limit]
```

- Sanitize `query_text` before the BM25 query (see [full-text-search](full-text-search.md)).
- The BM25 query cannot be restricted to a partition. For multi-tenant search, ask for a larger `LIMIT` (maximum 1000) and filter the BM25 results in the application. A small tenant in a large table can get no BM25 results. The ANN query can use a local vector index (see [filtering](filtering.md)).
- Fetch the full rows by primary key after the merge.
