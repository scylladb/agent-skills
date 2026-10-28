---
title: "Full-Text Search (BM25)"
tags: full-text-search, BM25, fulltext_index, keyword-search, hybrid-search
---

# Full-Text Search (BM25)

Full-text search needs ScyllaDB 2026.3.0 or later and the Vector Store (the same indexing nodes as Vector Search). Without a Vector Store, `CREATE CUSTOM INDEX ... USING 'fulltext_index'` succeeds, but queries fail with `Vector Store is disabled`. Read [Working with Full Text Search](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md) for the syntax.

## Rules

- Use this query shape only. ScyllaDB rejects all other shapes ([rules](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-queries)):

  ```sql
  SELECT id, body FROM blog.articles
    WHERE BM25(body, ?) > 0 ORDER BY BM25(body, ?) LIMIT 10;
  ```

- Bind the same value to both markers. `LIMIT` is 1000 at most, and results are not paged.
- Do not add other `WHERE` restrictions, including the partition key. Filter in the application. A filter that removes most rows (for example, one small tenant in a large table) can leave no results. Tell the user.
- Write `AND`, `OR`, `NOT` in uppercase. Lowercase `and` is a search term, so `a and b` silently means `a OR b`.
- Sanitize end-user input. Characters such as `:` `[` `^` and quotes make the query fail, also with bind markers ([example](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-drivers)).
- Select the [analyzer](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-analyzers) before you load data. It cannot change. The default `standard` analyzer does no stemming.
- Use [per-row TTL](https://cloud.docs.scylladb.com/stable/vector-search/work-with-vector-search.md#vs-ttl), not `USING TTL`. Expired cells stay in the index and use slots against `LIMIT`.

## Hybrid Search

As of ScyllaDB 2026.3, `BM25()` and `ANN OF` cannot be in one query, and BM25 scores are not returned. Put both indexes on one table ([example](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-hybrid)). Run both queries and merge the primary keys by rank with Reciprocal Rank Fusion. Python, with an open `session`:

```python
bm25 = session.prepare(
    "SELECT id FROM blog.docs WHERE BM25(body, ?) > 0 ORDER BY BM25(body, ?) LIMIT ?"
)
ann = session.prepare("SELECT id FROM blog.docs ORDER BY embedding ANN OF ? LIMIT ?")


def rrf(*ranked_lists, k=60):
    scores = {}
    for ranked in ranked_lists:
        for rank, key in enumerate(ranked, start=1):
            scores[key] = scores.get(key, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=scores.get, reverse=True)


def hybrid_search(text, vector, limit=10):
    keyword = [r.id for r in session.execute(bm25, (text, text, limit))]
    semantic = [r.id for r in session.execute(ann, (vector, limit))]
    return rrf(keyword, semantic)[:limit]
```
