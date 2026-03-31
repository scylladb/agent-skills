---
title: "Quantization and Rescoring"
tags: vector-search, quantization, f16, bf16, i8, b1, oversampling, rescoring, memory
---

# Quantization and Rescoring

Quantization reduces the memory footprint of the vector index by storing vectors at lower precision. This trades some search accuracy for significant memory savings.

## Overview

- **Quantization** compresses only the vector data in the in-memory index — the source vectors in the ScyllaDB table remain at full `float` precision
- **Oversampling** retrieves a larger candidate set to compensate for accuracy loss from quantization
- **Rescoring** re-calculates exact distances using full-precision vectors, then re-ranks candidates

## Quantization Levels

| Level | Size per Value | Compression vs. f32 | Accuracy | Use Case |
|-------|---------------|---------------------|----------|----------|
| `f32` (default) | 4 bytes | 1x (no compression) | Highest | Small datasets (<1M vectors), maximum accuracy |
| `f16` | 2 bytes | 2x | Very high | Moderate memory savings with minimal accuracy loss |
| `bf16` | 2 bytes | 2x | Very high | ML-optimized, similar to f16 |
| `i8` | 1 byte | 4x | High | Good balance for large datasets (1M-10M vectors) |
| `b1` | 0.125 bytes | 32x | Moderate | Maximum compression for very large datasets (>10M vectors) |

⚠️ **Actual total index memory savings are less than raw compression ratios** because the HNSW graph structure (neighbor lists, edge metadata) is not compressed. For example, `f32` → `i8` gives 4x reduction in vector storage, but total index memory typically drops ~3x.

## CQL Syntax

```sql
CREATE CUSTOM INDEX ON myapp.documents(embedding)
USING 'vector_index'
WITH OPTIONS = {
  'similarity_function': 'COSINE',
  'quantization': 'i8',
  'oversampling': '5.0',
  'rescoring': 'true'
};
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `quantization` | string | `'f32'` | Numeric precision: `f32`, `f16`, `bf16`, `i8`, `b1` |
| `oversampling` | string (float) | `'1.0'` | Multiplier for candidate set size. Range: 1.0-100.0 |
| `rescoring` | string (bool) | `'false'` | Second-pass exact distance using full-precision vectors |

## Oversampling

When a client requests the top K vectors, oversampling retrieves more candidates:

**Candidate pool size = ceil(K × oversampling)**

Candidates are sorted by distance and only the top K are returned.

- Range: 1.0 to 100.0
- Default: 1.0 (no oversampling)

Even without quantization, setting `oversampling` > 1.0 can improve recall on high-dimensionality datasets (≥768 dimensions).

## Rescoring

Rescoring re-calculates distances using the original full-precision vectors stored in the ScyllaDB table, then re-ranks candidates.

- `'true'` — ScyllaDB fetches original vectors and re-ranks by exact distance
- `'false'` (default) — results based on approximate distances from the quantized index

⚠️ **Rescoring reduces search throughput by ~4x** because ScyllaDB must fetch and recalculate for every candidate. Enable only when high recall is critical.

Rescoring is only beneficial with quantization. For unquantized indexes (`f32`), the index already has full precision — rescoring is redundant.

## Decision Guide

| Scenario | Quantization | Oversampling | Rescoring |
|----------|-------------|-------------|-----------|
| Small dataset, high recall required | `f32` (default) | 1.0 | false |
| Large dataset, memory-constrained | `i8` or `f16` | 3.0-10.0 | Only if very high recall needed |
| Very large dataset, approximate OK | `b1` | 5.0-20.0 | false (throughput priority) |
| High-dimensionality (≥768), any size | Consider any level | > 1.0 | Based on recall needs |

## Index Immutability

`ALTER INDEX` is **not supported** for vector indexes. To change quantization, oversampling, or rescoring settings, you must:

1. Drop the existing index: `DROP INDEX IF EXISTS myapp.my_idx;`
2. Recreate with new options: `CREATE CUSTOM INDEX ...`

The index will be rebuilt from the stored data, which takes time proportional to the number of vectors.
