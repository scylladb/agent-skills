---
title: ScyllaCluster Configuration
impact: CRITICAL
impactDescription: Manual overrides that fight the Operator's own management, or a rack/zone layout that doesn't match your replication factor, undermine the availability guarantees ScyllaDB is meant to provide
tags: kubernetes, scyllacluster, replication-factor, affinity, resources
---

## Anti-Pattern: Overriding Operator-Managed Config

A `ScyllaCluster` can reference a ConfigMap (via `scyllaConfig`) containing a `scylla.yaml` for application-level tuning, authenticator, authorizer, buffer sizes, compaction throughput, and similar settings are safe to set there. But networking, listen addresses, broadcast addresses, and seed nodes must **not** be set in this ConfigMap. The Operator manages these automatically based on the Kubernetes environment, and any conflicting value supplied manually is simply overridden. Setting them anyway doesn't cause an error, it just silently does nothing, which makes the mistake easy to miss during review.

```yaml
# Correct: application-level tuning only
apiVersion: v1
kind: ConfigMap
metadata:
  name: scylladb-config
data:
  scylla.yaml: |
    authenticator: PasswordAuthenticator
    authorizer: CassandraAuthorizer
    # other application-level options — fine here
    # do NOT add listen_address, broadcast_address, seed_provider, etc.
```

## Racks Map to Replication Factor, Not to Convenience

Kubernetes clusters are a regional concept; a `ScyllaCluster`'s `datacenter` maps to a ScyllaDB datacenter, and each `rack` within it should map to a distinct Kubernetes availability zone. The rule of thumb from ScyllaDB's own documentation: **use as many racks as your desired replication factor.** An RF=3 cluster should be spread across 3 racks/zones, fewer than that and a single zone failure can take out more replicas than the replication factor was designed to tolerate.

```yaml
placement:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values: ["<zone>"]
            - key: scylla.scylladb.com/node-type
              operator: In
              values: ["scylla"]
  tolerations:
    - key: scylla-operator.scylladb.com/dedicated
      operator: Equal
      value: scyllaclusters
      effect: NoSchedule
```

## Pod Anti-Affinity: One ScyllaDB Pod Per Node

In addition to zone-level `nodeAffinity`, production examples add `podAntiAffinity` keyed on `kubernetes.io/hostname` so that no two ScyllaDB pods from the same cluster land on the same physical node, defeating the purpose of running multiple replicas if a single node failure could take out more than one of them:

```yaml
placement:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: kubernetes.io/hostname
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: scylla
            scylla/cluster: <cluster-name>
```

## Resources: Two Separate Blocks, Easy to Forget One

Every ScyllaDB pod also runs the ScyllaDB Manager Agent as a sidecar container. A `ScyllaCluster` manifest needs **both** `resources` (for the ScyllaDB container) and `agentResources` (for the Manager Agent sidecar) specified, with requests equal to limits in both, to get Guaranteed QoS (see `node-preparation-and-storage.md` for why that matters). Forgetting `agentResources` is a common omission since it's easy to assume `resources` alone covers the whole pod.

```yaml
resources:
  requests: { cpu: "6", memory: 50Gi }
  limits:   { cpu: "6", memory: 50Gi }
agentResources:
  requests: { cpu: 100m, memory: 20Mi }
  limits:   { cpu: 100m, memory: 20Mi }
```

## Other Fields Worth Setting Deliberately

- `developerMode`: `true` for quick local evaluation (relaxes some production safety checks), `false` for anything resembling production. Don't leave this on `true` by default in a template meant to be reused.
- `automaticOrphanedNodeCleanup: true` — lets the Operator clean up Kubernetes-level resources left behind by a ScyllaDB node that was replaced, worth enabling rather than leaving cleanup to be manual.
- `storageClassName: scylladb-local-xfs` (or your equivalent) must point at a StorageClass that actually provisions XFS-formatted local storage, see `node-preparation-and-storage.md`, this field alone doesn't create that guarantee, the underlying StorageClass has to back it up.
