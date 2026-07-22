---
title: Compatibility Differences From Real DynamoDB
impact: HIGH
impactDescription: Silent behavioral differences that can change application results or resource usage when DynamoDB code is ported unmodified
tags: alternator, compatibility, migration, dynamodb-differences, tablets
---

## Compatibility Differences From Real DynamoDB

Before telling a user that a DynamoDB application will "just work" unmodified against Alternator, flag the differences below. None of these are bugs; they are documented, intentional differences, but each one can silently change application behavior if the application implicitly depended on DynamoDB-specific behavior.

### Consistency Mapping

DynamoDB's "eventually consistent" reads map to ScyllaDB's `LOCAL_ONE` consistency level. "Strongly consistent" reads, and all writes, map to `LOCAL_QUORUM`. This mapping is fixed, not tunable per-request the way DynamoDB's `ConsistentRead` boolean parameter might suggest to someone reasoning from DynamoDB's model alone.

### Scan Order Is Different

DynamoDB scans return partitions in an undocumented hash order specific to DynamoDB's internal hash function. Alternator uses Cassandra's Murmur3 hash instead, which produces a different partition order for the same data. Within a partition, sort-key order is identical between the two. An application that (incorrectly, per DynamoDB's own documentation) depends on scan order will see different, not wrong, results — this is worth explaining to a user who reports "the data looks reordered."

### BatchWriteItem Item Limits Differ

DynamoDB hard-caps `BatchWriteItem` at 25 items per request. Alternator defaults to 100 items, configurable via the `alternator_max_items_in_batch_write` configuration parameter. Application code hardcoded around DynamoDB's 25-item limit will simply underuse Alternator's higher ceiling rather than break — worth mentioning as an opportunity, not just a difference.

### Attribute Storage

DynamoDB items can have arbitrary nested attributes. Under Alternator, all non-key attributes of an item are stored in a single ScyllaDB map column, not as individual ScyllaDB columns. This matters if the user later wants to query or index a specific nested attribute directly with CQL against the underlying table, rather than exclusively through the DynamoDB API — that access pattern is more constrained than it would be for a table designed as CQL-native from the start.

### Tablets and the Initial-Tablets Tag

As of ScyllaDB 2025.4, Alternator tables follow the cluster-wide `tablets_mode_for_new_keyspaces` flag by default. To override per-table at creation time, set a tag on `CreateTable`:

- Tag name on current ScyllaDB versions: `system:initial_tablets`
- Tag name on ScyllaDB versions prior to the rename: `experimental:initial_tablets`
- Value: any integer enables tablets (`0` lets ScyllaDB pick a reasonable initial count; any other integer overrides it); a non-integer value such as `"none"` forces vnodes instead

Check the target ScyllaDB version before giving a user a tag name — using the pre-rename or post-rename name on the wrong version will silently do nothing rather than raise an error, which makes the mistake hard to notice.

### Table Deletion Wastes Disk Space by Default

ScyllaDB snapshots a table automatically when it's deleted, but Alternator provides no API to restore from that snapshot. A DynamoDB-style `DeleteTable` call therefore leaves an unusable, unrecoverable snapshot consuming disk. Recommend setting `auto_snapshot: false` in `scylla.yaml` on Alternator-enabled clusters rather than letting this accumulate silently.

### Flagged as Needing Re-Verification, Not Stated as Current Fact

The following two items appear in ScyllaDB's documentation, but the specific copy this was sourced from was last dated around 2021, and Alternator has changed substantially since then (tablets support alone landed in 2025.4). Re-verify against current ScyllaDB documentation before repeating either of these to a customer as a current limitation:

- **Multi-region "global tables"**: `CreateGlobalTable`, `UpdateGlobalTable`, `DescribeGlobalTable`, and related multi-region DynamoDB APIs were, as of that documentation, not implemented.
- **On-demand / continuous backup APIs**: `CreateBackup`, `RestoreTableFromBackup`, and point-in-time restore APIs were, as of that same documentation, not implemented; ScyllaDB snapshots or ScyllaDB Manager were suggested as the replacement.
