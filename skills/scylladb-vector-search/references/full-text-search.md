---
title: "Full-Text Search (BM25)"
tags: full-text-search, BM25, fulltext_index, keyword-search, analyzer
---

# Full-Text Search (BM25)

Full-text search ranks rows by BM25 relevance from a `fulltext_index` on a text column. It needs ScyllaDB 2026.3.0 or later and runs on the same indexing nodes (the Vector Store) as Vector Search. Full guide: [Working with Full Text Search](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md).

## Requirements

- ScyllaDB Cloud: a cluster with Vector and Text Search enabled, on ScyllaDB 2026.3.0 or later ([deployments](https://cloud.docs.scylladb.com/stable/vector-search/vector-search-clusters.md)).
- Locally: a connected Vector Store container (see [local-docker](local-docker.md)). Without one, `CREATE CUSTOM INDEX ... USING 'fulltext_index'` succeeds, but every query fails with `Vector Store is disabled`.
- The column is `text`, `varchar` or `ascii`, and is not a partition key column. The keyspace uses tablets. CDC is enabled automatically.

## Query Shape

A full-text query has exactly one valid shape. ScyllaDB rejects every other shape ([rules and errors](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-queries)):

```cql
SELECT id, body FROM blog.articles
  WHERE BM25(body, 'search terms') > 0
  ORDER BY BM25(body, 'search terms')
  LIMIT 10;
```

- Use the same column and the same term in `WHERE` and `ORDER BY`. In prepared statements, bind the same value to both markers.
- `LIMIT` is required, with a maximum of 1000. Results are never paged.
- Do not add other `WHERE` restrictions, including the partition key. `ALLOW FILTERING` does not help. Filter in the application after the query. Because of the `LIMIT` maximum, a filter that removes most rows (for example, one small tenant in a large table) can leave no results. Tell the user about this limit.
- Do not put `BM25()` in the `SELECT` list. Scores are not returned as of 2026.3.

Wrong, because these are rejected or are not full-text search:

```cql
SELECT * FROM blog.articles WHERE body LIKE '%distributed%';
SELECT * FROM blog.articles WHERE tenant = 'a' AND BM25(body, 'x') > 0 ORDER BY BM25(body, 'x') LIMIT 10;
SELECT id, BM25(body, 'x') AS score FROM blog.articles WHERE BM25(body, 'x') > 0 ORDER BY BM25(body, 'x') LIMIT 10;
```

## Query String Traps

The `BM25()` string uses a [text query language](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-query-language), not CQL.

- Write `AND`, `OR`, `NOT` in uppercase. Lowercase `and` is a term, so `distributed and apple` silently means `distributed OR apple`.
- Separate terms without an operator are joined with `OR`.
- Put phrases in double quotes inside the CQL string: `'"theory of relativity"'`. Phrases need `'positions': 'true'` (the default).
- Do not rely on fuzzy (`term~1`) or prefix (`term*`) syntax.
- Characters such as `:`, `[`, `{`, `^`, quotes and unbalanced parentheses make the query fail. Bind markers do not prevent this. Sanitize end-user input before the query, as in the [driver example](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-drivers).

## Analyzer

- Select the analyzer before you load data. It cannot change after creation. To change it, drop and create the index again, which rebuilds it.
- The default `standard` analyzer removes English stop words and does no stemming. For stemming, or for text in another language, use a language analyzer such as `english` or `german` ([analyzers](https://cloud.docs.scylladb.com/stable/vector-search/full-text-search.md#fts-analyzers)).

```cql
CREATE CUSTOM INDEX IF NOT EXISTS articles_body_fts ON blog.articles(body)
  USING 'fulltext_index'
  WITH OPTIONS = {'analyzer': 'english'};
```

## Index Build, Writes and TTL

- After `CREATE CUSTOM INDEX`, queries fail with `404 ... missing index` and then `503 ... still being constructed` until the build completes. Retry until the query succeeds.
- Writes become searchable a few seconds after the write. To read a write immediately, read the row by primary key.
- Do not use cell-level TTL (`USING TTL`, `default_time_to_live`). Expired rows stay in the index and use slots against `LIMIT`, so queries can return fewer rows. Use [per-row TTL](https://cloud.docs.scylladb.com/stable/vector-search/work-with-vector-search.md#vs-ttl).
- `TRUNCATE` does not clear the index, as for vector indexes (see [vector-type-and-indexing](vector-type-and-indexing.md)).
