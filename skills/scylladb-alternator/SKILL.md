---
name: scylladb-alternator
description: Guide users building against ScyllaDB's DynamoDB-compatible API (Alternator). Use this skill when a user is porting a DynamoDB application to ScyllaDB, using boto3/AWS SDK clients against ScyllaDB, or asking about Alternator setup, write isolation, or load balancing. Triggers on "Alternator", "DynamoDB API", "DynamoDB compatible", "boto3 with ScyllaDB", "migrate from DynamoDB", "aws-sdk against ScyllaDB", "alternator_port", "alternator_write_isolation".
---

# ScyllaDB Alternator (DynamoDB-Compatible API)

Alternator is ScyllaDB's DynamoDB-compatible API: JSON requests over HTTP/HTTPS, using the same wire protocol and (mostly) the same client SDKs as Amazon DynamoDB. The goal is that an application written for DynamoDB can run against ScyllaDB largely unmodified. It is not a separate database; Alternator tables are ordinary ScyllaDB tables underneath, each in its own keyspace, with the DynamoDB hash/sort key becoming the ScyllaDB partition/clustering key.

## When to Use This Skill

- The user is migrating an existing DynamoDB application to ScyllaDB
- The user is using `boto3`, `aws-sdk-java`, or another AWS SDK client, with a custom `endpoint_url` pointed at a ScyllaDB cluster
- The user asks about `alternator_port`, `alternator_write_isolation`, or DynamoDB-style table creation against ScyllaDB
- The user needs to know what does or doesn't carry over from real DynamoDB behavior

For schema design guidance once data is in ScyllaDB (partition keys, clustering, anti-patterns), defer to the `scylladb-data-modeling` skill — Alternator tables are still subject to the same partition-key and hot-partition considerations underneath the DynamoDB-shaped API.

## Enabling Alternator

Alternator is off by default. Two configuration options are required, and there is no default for the second one — starting ScyllaDB with `alternator_port` set but without `alternator_write_isolation` will fail with an explicit error:

```yaml
alternator_port: 8000
alternator_write_isolation: only_rmw_uses_lwt   # or: always, forbid, unsafe
```

Equivalently, as command-line flags: `--alternator-port=8000 --alternator-write-isolation=only_rmw_uses_lwt`.

See `references/write-isolation-policies.md` for what each of the four policy values actually does and which to recommend.

For local testing (Docker):

```bash
docker run --name scylla -d -p 8000:8000 scylladb/scylla:latest \
  --alternator-port=8000 --alternator-write-isolation=always
```

By default this has no authentication enabled; any signed or unsigned request is honored. Do not leave a cluster this way outside of local testing — see `references/connecting-and-load-balancing.md` for real authentication and load-balancing setup.

## Quick Reference

### Reference Files — 3

- [write-isolation-policies](references/write-isolation-policies.md) — The four write isolation policies, what each one costs and protects against, and which to recommend by default. Consult when configuring a new Alternator-enabled cluster or reviewing why an existing one is slow or inconsistent under concurrent writes.
- [connecting-and-load-balancing](references/connecting-and-load-balancing.md) — Why Alternator has no single endpoint the way DynamoDB does, how authentication maps to CQL roles, and how to discover nodes for client-side load balancing. Consult before pointing any DynamoDB SDK client at a real (non-single-node-test) ScyllaDB cluster.
- [compatibility-differences](references/compatibility-differences.md) — Behavioral differences from real DynamoDB that can silently change application behavior when porting code: consistency mapping, scan ordering, batch limits, attribute storage, tablets, and table deletion. Consult when migrating an existing DynamoDB application rather than building new against Alternator.

## Local Testing

```bash
pip install boto3
```

```python
import boto3
dynamodb = boto3.resource(
    'dynamodb',
    endpoint_url='http://localhost:8000',
    region_name='None',
    aws_access_key_id='None',
    aws_secret_access_key='None'
)
# region_name/access_key/secret_key are placeholders here only because the
# local test cluster above was started with no authentication enabled.
# Never do this against a real cluster — see connecting-and-load-balancing.md.
```

## Vector Search Extension

ScyllaDB Cloud offers an Alternator-specific extension for approximate nearest neighbor (ANN) search directly on DynamoDB-style item attributes, requiring no additional client library. If the user is doing similarity search through the DynamoDB API rather than CQL, point them to this rather than assuming they need to switch to a CQL client to get vector search.
