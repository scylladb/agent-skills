---
name: scylladb-vector-search
description: Guides users through implementing and optimizing ScyllaDB Vector Search for semantic similarity, RAG, and similar use cases. Use this skill when users need to store and query embeddings, build vector indexes (HNSW), run approximate nearest neighbour (ANN) queries, apply filtering (global/local secondary indexes), configure quantization, integrate with LLM frameworks (e.g. LangChain), or run Vector Search locally with Docker for testing. Schema design outside the vector column goes to scylladb-data-modeling. Triggers on "vector", "embeddings", "similarity search", "ANN", "nearest neighbor", "RAG", "semantic search", "recommendation system", "vector index", "HNSW", "vector-store".
---

# ScyllaDB Vector Search

If the task goes beyond this skill, use the parent `scylladb` skill for a ScyllaDB overview and the list of other ScyllaDB skills. If it is not installed, fetch it from `https://raw.githubusercontent.com/scylladb/agent-skills/main/skills/scylladb/SKILL.md`.

Vector Search stores embeddings in a `vector<float, N>` column and answers approximate nearest neighbor (ANN) queries from an HNSW vector index. For production it is available only on ScyllaDB Cloud. The index is maintained outside the table, so `TRUNCATE` does not clear it.

## When to Use This Skill

- The user wants to store embeddings in ScyllaDB and run similarity search
- The user is building semantic search, RAG, or a recommendation system on ScyllaDB
- The user is creating a vector index or tuning HNSW parameters
- The user needs to combine ANN queries with filters on other columns
- The user wants to reduce vector index memory with quantization
- The user needs a driver version that supports the `vector` CQL type
- The user wants to try Vector Search locally or in CI with Docker

For adjacent topics, use the sibling skill instead:

- Partition keys and table design for the non-vector parts of the schema: `scylladb-data-modeling`
- Connecting to the Cloud cluster and choosing a driver: `scylladb-cloud-setup`
- Similarity search through the DynamoDB API instead of CQL: `scylladb-alternator`

## Where Vector Search Runs

- **Production: ScyllaDB Cloud only.** Vector Search runs on dedicated indexing nodes that ScyllaDB Cloud manages and syncs from the storage nodes through CDC. Self-hosted and on-prem deployments are not supported. If the user plans one of these for production, tell them that Vector Search requires a standard ScyllaDB Cloud cluster with Vector Search enabled.
- **Development and testing: local Docker.** Run a ScyllaDB container plus a separate `scylladb/vector-store` container (the indexing service) connected to it. See [local-docker](references/local-docker.md).

## Core Principles

1. **Understand before building** — Validate the use case to ensure Vector Search is the right solution
2. **Inspect schema first** — Check existing tables and indexes before making recommendations
3. **Explain before executing** — Describe what indexes will be created and confirm before proceeding
4. **Start with defaults** — Use default HNSW parameters and no quantization; tune only when needed

## Workflow

### 1. Discovery Phase

**Understand the use case:**
- What type of data are they searching? (text, images, audio, structured data)
- What embedding model are they using or planning to use?
- How many vectors will they store? (affects quantization decision)
- Do they need filtering alongside similarity search? (affects index type: global vs. local)
- What latency/throughput requirements do they have?

Common use cases:
- **Semantic search** — Find documents/passages matching the meaning of a query
- **RAG (Retrieval-Augmented Generation)** — Provide relevant context to an LLM
- **Recommendation systems** — Find items similar to those a user interacted with
- **Image/audio search** — Find visually or acoustically similar media
- **Anomaly detection** — Identify outliers far from clusters in vector space
- **Deduplication** — Find near-duplicate records

### 2. Determine Requirements

Before creating tables and indexes, establish:

| Parameter | How to Determine |
|-----------|-----------------|
| Dimensions | From the embedding model (e.g., 384, 768, 1536) |
| Similarity function | From the embedding model docs (`COSINE` is default and safe for most) |
| Need filtering? | Does the query combine similarity with metadata constraints? |
| Dataset size | < 1M vectors → no quantization; 1M-10M → consider `i8`; > 10M → consider `b1` |

### 3. Consult Reference Files

Always consult the matching file in the [Quick Reference](#quick-reference) before recommending indexes or queries.

### 4. Implementation

**Typical implementation order:**

1. Create a keyspace (tablets are enabled by default)
2. Create a table with a `vector<float, N>` column
3. Insert vectors (from your embedding pipeline)
4. Create a vector index (`CREATE CUSTOM INDEX ... USING 'vector_index'`)
5. Run ANN queries (`ORDER BY vec_col ANN OF [...] LIMIT k`)
6. Add filtering if needed (local index preferred for performance)
7. Add quantization if needed for memory savings

### 5. Validation

After setup, verify:
- The ANN query returns results (wait ~1 second after inserting vectors to account for write-to-query latency)
- Similarity scores are in the expected range (0-1, higher = more similar)
- Filtered queries return correctly filtered results

## Anti-Patterns to Avoid

**NEVER use `ALLOW FILTERING` with vector search when a local index would work:**
Global vector indexes require `ALLOW FILTERING` when adding a `WHERE` clause and are always much slower than local indexes. Design the schema so filter columns are part of the partition key and use a local vector index.

**NEVER mix embedding models:**
Vectors from different embedding models live in incompatible vector spaces. If you change the model, you must re-embed and re-index all data.

**NEVER skip the LIMIT clause:**
ANN queries require a `LIMIT` — ScyllaDB will reject the query without one.

## Handling Edge Cases

**User doesn't have an embedding model yet:**
- Recommend starting with `all-MiniLM-L6-v2` (384 dims, open weights, good general-purpose)
- For production: suggest evaluating OpenAI or Cohere embedding models

**User's cluster doesn't have Vector Search enabled:**
- Direct them to the ScyllaDB Cloud UI → cluster settings → enable Vector Search
- See [Vector Search Deployments](https://cloud.docs.scylladb.com/stable/vector-search/vector-search-clusters.md) for setup
- On a local Docker setup, check that the `vector-store` container is running and ScyllaDB has `--vector-store-primary-uri` set (see [local-docker](references/local-docker.md))

**Query returns no results:**
- Check write-to-query latency (~1 second delay after insert)
- Verify the query vector dimensions match the index dimensions
- Verify the index was created successfully
- Ensure the embedding model is the same for indexing and querying

**TTL is needed:**
- Vector indexes do not support TTL. Workaround: use application-level deletion with a background job that deletes expired rows.

**User wants to clear all vectors (reset the table):**
- `TRUNCATE` does **not** clear the vector index. The vector store updates its index only through CDC, and `TRUNCATE` is not propagated to CDC — the `CUSTOM INDEX` remains, and previously indexed vectors stay in memory.
- The only correct solution is to **drop and recreate both the table and the custom index**. See [vector-type-and-indexing](references/vector-type-and-indexing.md) for the exact DDL.

## Quick Reference

- [vector-type-and-indexing](references/vector-type-and-indexing.md) — The `vector` type, the tablets requirement, `CREATE CUSTOM INDEX ... USING 'vector_index'`, similarity functions, HNSW parameters, and why `TRUNCATE` does not clear the index. Consult before creating a vector table or index, or when the user wants to reset vector data.
- [ann-queries](references/ann-queries.md) — `ORDER BY ... ANN OF ... LIMIT` syntax, similarity scores, write-to-query latency, and CQL features that ANN queries do not support. Consult when writing or debugging an ANN query.
- [filtering](references/filtering.md) — Global vs. local vector indexes, schema design for filtered and multi-tenant search, and their limitations. Consult when an ANN query needs a `WHERE` clause.
- [quantization](references/quantization.md) — Quantization levels (`f16`, `bf16`, `i8`, `b1`), oversampling, rescoring, and why index options cannot change after creation. Consult when the dataset is over about 1M vectors or index memory is a concern.
- [driver-integration](references/driver-integration.md) — Minimum driver versions for the `vector` type and insert/query examples in Python, Java, Go, and Node.js. Consult when writing application code that reads or writes vectors.
- [local-docker](references/local-docker.md) — Running ScyllaDB and the Vector Store service together in Docker, the flags and environment variables that connect them, and why this setup is not for production. Consult when the user wants Vector Search locally, in CI, or in tests, or has no ScyllaDB Cloud cluster.
