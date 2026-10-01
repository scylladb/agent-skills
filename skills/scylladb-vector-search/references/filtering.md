---
title: "Filtering Vector Search Results"
tags: vector-search, filtering, global-index, local-index, partition-key, filtering-columns, WHERE
---

# Filtering Vector Search Results

Fetch the official guide for syntax, examples, and limitations before recommending a filtering schema:
https://cloud.docs.scylladb.com/stable/vector-search/vector-search-filtering.md

It covers global vs. local vector indexes, local indexes keyed on non-primary-key columns, filtering columns, and when `ALLOW FILTERING` is required.

## Choosing a Schema

Scope searches with a local vector index whose partition key is the column you filter on most (tenant, user, etc.), queried with `=`:

1. **The scoping column fits the base table's partition key**: put it there and build the local index on it.
2. **It doesn't fit** (nullable, the table is read and deleted by id, or some tenants are very large): key the local index on the regular column instead of redesigning the base table's primary key.
3. **Secondary constraints** (country, visibility, category): add them as filtering columns after the vector column.

## Misleading Error

Filtering a global index on a non-PK column that isn't a filtering column fails with `Global ANN query is not supported when only a local vector index is available`. The fix is to add the column to the index as a filtering column, not to create a local index.
