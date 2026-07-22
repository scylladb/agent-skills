---
title: Write Isolation Policies
impact: CRITICAL
impactDescription: Controls correctness vs. performance trade-off for every write; has no default and must be set explicitly
tags: alternator, write-isolation, lwt, rmw, configuration
---

## Write Isolation Policies

DynamoDB's API includes read-modify-write (RMW) operations — conditional updates, atomic counters, requests that return old attribute values — that need isolation from concurrent writes to the same item. Alternator implements this isolation using ScyllaDB's LWT (lightweight transactions), but LWT has a real performance cost, so the policy is configurable per-cluster, and can be overridden per-table via a tag. There is no default: a cluster started with `alternator_port` set but no `alternator_write_isolation` value will fail to start with an explicit error asking for one.

### The Four Policies

**`always`**
Every write, RMW or not, uses LWT. Safest option, and the correct starting point for local testing or when the application's write pattern isn't yet characterized. Slowest of the four.

**`only_rmw_uses_lwt`**
Only writes that are actually read-modify-write use LWT; plain unconditional writes skip it. This is usually the right recommendation for production once the application's behavior is understood, since it gets the isolation guarantee only where DynamoDB semantics actually require it.

**`forbid`**
RMW operations are rejected outright rather than paying the LWT cost. Only appropriate if the application is verified not to use conditional updates, atomic counters, or "return old values" semantics. Recommending this without confirming the application doesn't rely on RMW semantics risks silent request failures in production.

**`unsafe`**
No LWT is used even for RMW operations. Concurrent conditional updates or counter increments are not properly isolated under this setting — two concurrent RMW writes to the same item can race in ways that would not happen on real DynamoDB or under the other three policies. Fastest option, but do not recommend this as a default, and flag explicitly to the user what "unsafe" means here rather than assuming the name is self-explanatory enough.

### How to Choose

1. Start with `always` while characterizing the application's actual write pattern
2. Confirm which write paths are genuinely RMW (conditional updates, counters, "old value" returns) versus plain writes
3. Move to `only_rmw_uses_lwt` once that's confirmed, as the normal production setting
4. Only consider `forbid` or `unsafe` for a specific table where the performance need is proven and the correctness trade-off is understood and accepted, not as a blanket cluster-wide default
