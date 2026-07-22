---
title: Connecting and Load Balancing
impact: HIGH
impactDescription: DynamoDB SDK clients assume a single managed endpoint; Alternator provides no equivalent, so unmodified DynamoDB code will bottleneck on one node in production
tags: alternator, load-balancing, authentication, connectivity
---

## No Single Endpoint

Real DynamoDB gives an application a single regional endpoint (e.g. `dynamodb.us-east-1.amazonaws.com`) behind AWS-managed load balancing. Alternator does not provide this. Every ScyllaDB node serves Alternator requests directly, and the client is responsible for distributing requests across nodes, either with an external load balancer or a client-side load-balancing library.

This is one of the most common gaps when someone ports DynamoDB code unmodified: the code will work fine against a single node in local testing, and then bottleneck on that one node, or fail over unevenly, once pointed at a real multi-node cluster in production. Flag this explicitly rather than letting a user assume connecting to any one node's address is sufficient for production traffic.

### Node Discovery

Alternator exposes two unauthenticated HTTP endpoints to support building a load-balancing layer:

- `GET /` — liveness check of the contacted node (unauthenticated, same as real DynamoDB's equivalent)
- `GET /localnodes` — lists nodes in the same datacenter as the contacted node. Accepts optional query parameters:
  - `?dc=<name>` — list nodes in a specific datacenter rather than the contacted node's own
  - `?rack=<name>` — list nodes in a specific rack only

A typical setup uses one load balancer per datacenter, mirroring how real DynamoDB has one endpoint per AWS region.

## Authentication

Alternator reuses ScyllaDB's own CQL role system rather than AWS IAM. Create a CQL role, and use the role name as the AWS access key ID and the role's salted password hash as the AWS secret access key:

```sql
SELECT salted_hash FROM system.roles WHERE role = 'myrole';
```

The client signs requests exactly as it would for real DynamoDB (same signature protocol), just with these substituted credentials.

Authorization (which role can do what) is implemented, but is **not** compatible with DynamoDB's IAM-policy or `PutResourcePolicy` model. Do not assume IAM policy syntax or semantics carry over when a user asks about restricting table access by role.

## What Not to Do

- Do not point a DynamoDB SDK client at a single node's address and call it production-ready; that address needs to sit behind a load balancer or client-side load-balancing library
- Do not assume an IAM policy document written for real DynamoDB access control will mean anything to Alternator's authorization model
- Do not leave a cluster running with Alternator enabled and no authentication configured outside of local, throwaway testing
