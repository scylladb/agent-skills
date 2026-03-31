---
title: "Query-First Design"
impact: CRITICAL
impactDescription: "The foundational methodology for ScyllaDB data modeling — get this wrong and everything else fails"
tags: data-modeling, fundamentals, query-first, access-patterns, denormalization
---

## Query-First Design

**In ScyllaDB, tables are designed to serve specific queries — not to represent entities.** This is the single most important concept in ScyllaDB data modeling. If you design tables like SQL (entity-first) or MongoDB (document-first), your queries will be slow, require `ALLOW FILTERING`, or fail entirely.

### The Methodology

**Step 1: List every query your application will run**

Write down every `SELECT` statement your application needs. Be specific about:
- Which columns are in the `WHERE` clause
- Which columns need to be returned
- What sort order is needed
- Whether range queries are required

Example queries for a messaging app:
```
Q1: Get all messages in a conversation, newest first
Q2: Get all conversations for a user
Q3: Get unread message count per conversation for a user
```

**Step 2: Design one table per query**

Each query becomes a table. The `WHERE` clause columns become the primary key.

**Q1 → `messages_by_conversation`:**

```sql
CREATE TABLE messages_by_conversation (
    conversation_id uuid,
    sent_at timestamp,
    sender_id uuid,
    body text,
    PRIMARY KEY (conversation_id, sent_at)
) WITH CLUSTERING ORDER BY (sent_at DESC);
```

- `conversation_id` is the partition key (all messages in a conversation live together)
- `sent_at` is the clustering column (messages sorted newest-first)
- Query: `SELECT * FROM messages_by_conversation WHERE conversation_id = ?`

**Q2 → `conversations_by_user`:**

```sql
CREATE TABLE conversations_by_user (
    user_id uuid,
    updated_at timestamp,
    conversation_id uuid,
    last_message_preview text,
    PRIMARY KEY (user_id, updated_at)
) WITH CLUSTERING ORDER BY (updated_at DESC);
```

- Query: `SELECT * FROM conversations_by_user WHERE user_id = ?`

**Q3 → `unread_counts_by_user`:**

```sql
CREATE TABLE unread_counts_by_user (
    user_id uuid,
    conversation_id uuid,
    unread_count counter,
    PRIMARY KEY (user_id, conversation_id)
);
```

- Query: `SELECT * FROM unread_counts_by_user WHERE user_id = ?`

**Step 3: Accept the duplication**

The same data (conversation metadata, message info) may be written to multiple tables. This is expected and correct. In ScyllaDB, write amplification (writing to multiple tables) is cheap — reads that hit the wrong table structure are expensive.

### Incorrect (entity-first, SQL-style)

```sql
-- WRONG: Designing tables around entities, not queries
CREATE TABLE users (
    user_id uuid PRIMARY KEY,
    name text,
    email text
);

CREATE TABLE conversations (
    conversation_id uuid PRIMARY KEY,
    title text,
    created_at timestamp
);

CREATE TABLE messages (
    message_id uuid PRIMARY KEY,
    conversation_id uuid,
    sender_id uuid,
    body text,
    sent_at timestamp
);

-- This query requires ALLOW FILTERING — a full table scan
SELECT * FROM messages WHERE conversation_id = ? ORDER BY sent_at DESC;
-- Because conversation_id is NOT the partition key
```

### When NOT to Denormalize

- **Very low-volume lookup tables** (e.g., configuration, feature flags) — a single table with simple lookups is fine
- **When write consistency is critical** — denormalized writes to multiple tables are not atomic (consider using `BATCH` for single-partition atomicity, or LWT for linearizable single-partition operations)
