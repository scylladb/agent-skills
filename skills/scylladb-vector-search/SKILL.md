---
name: scylladb-vector-search
description: |
  Guides ScyllaDB Cloud users through implementing and optimizing Vector Search for semantic similarity, RAG, and similar use cases. Use this skill when users need to store and query embeddings, build vector indexes (HNSW), run approximate nearest neighbour (ANN) queries, apply filtering (global/local secondary indexes), configure quantization, or integrate with LLM frameworks (e.g. LangChain). Also use when users mention "vector", "embeddings", "similarity search", "ANN", "nearest neighbor", "RAG", "semantic search", or "recommendation system" in the context of ScyllaDB.
---

# ScyllaDB Vector Search

You are helping ScyllaDB Cloud users implement, optimize, and troubleshoot Vector Search for similarity-based queries. Your goal is to understand their use case, recommend the right configuration, and help them build effective vector indexes and ANN queries.

## ⚠️ ScyllaDB Cloud Only

Vector Search is a **ScyllaDB Cloud feature**. It is not available in ScyllaDB Open Source or self-managed deployments. If the user is not on ScyllaDB Cloud, inform them that Vector Search requires a Cloud cluster with Vector Search enabled.

## Core Principles

1. **Understand before building** — Validate the use case to ensure Vector Search is the right solution
2. **Inspect schema first** — Check existing tables and indexes before making recommendations
3. **Explain before executing** — Describe what indexes will be created and confirm before proceeding
4. **Start with defaults** — Use default HNSW parameters and no quantization; tune only when needed
5. **DC-aware is mandatory** — Vector Search requires the driver to use a DC-aware load balancing policy

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

Always consult the appropriate reference file(s) before recommending indexes or queries:

- **Table + index creation**: consult `references/vector-type-and-indexing.md`
- **ANN queries**: consult `references/ann-queries.md`
- **Filtering (global vs. local indexes)**: consult `references/filtering.md`
- **Quantization / memory optimization**: consult `references/quantization.md`
- **Driver setup for vector search**: consult `references/driver-integration.md`

### 4. Implementation

**Typical implementation order:**

1. Create a keyspace (tablets enabled — default in ScyllaDB Cloud)
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
- Driver is configured with DC-aware load balancing policy

## Anti-Patterns to Avoid

**NEVER use `ALLOW FILTERING` with vector search when a local index would work:**
Global vector indexes require `ALLOW FILTERING` when adding a `WHERE` clause and are always much slower than local indexes. Design the schema so filter columns are part of the partition key and use a local vector index.

**NEVER mix embedding models:**
Vectors from different embedding models live in incompatible vector spaces. If you change the model, you must re-embed and re-index all data.

**NEVER skip the LIMIT clause:**
ANN queries require a `LIMIT` — ScyllaDB will reject the query without one.

## Handling Edge Cases

**User doesn't have an embedding model yet:**
- Recommend starting with `all-MiniLM-L6-v2` (384 dims, open-source, good general-purpose)
- For production: suggest evaluating OpenAI or Cohere embedding models

**User's cluster doesn't have Vector Search enabled:**
- Direct them to the ScyllaDB Cloud UI → cluster settings → enable Vector Search
- See [Vector Search Deployments](https://cloud.docs.scylladb.com/stable/vector-search/vector-search-clusters.html) for setup

**Query returns no results:**
- Check write-to-query latency (~1 second delay after insert)
- Verify the query vector dimensions match the index dimensions
- Verify the index was created successfully
- Ensure the embedding model is the same for indexing and querying

**TTL is needed:**
- Vector indexes do not support TTL. Workaround: use application-level deletion with a background job that deletes expired rows.
