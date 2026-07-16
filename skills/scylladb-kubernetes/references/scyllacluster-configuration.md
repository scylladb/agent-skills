---
title: ScyllaCluster Configuration
impact: CRITICAL
impactDescription: Manual overrides that fight the Operator's own management, or a rack/zone layout that doesn't match your replication factor, undermine the availability guarantees ScyllaDB is meant to provide
tags: kubernetes, scyllacluster, replication-factor, affinity, resources
---

## The Full Template: `datacenter` → `racks` → `members`

The single-node manifest in the Operator's getting-started docs is deliberately minimal, it exists to prove the Operator works, not to model a real deployment. A production `ScyllaCluster` is a three-level topology: one `datacenter` (a Kubernetes region), containing multiple `racks` (each pinned to a distinct availability zone), each with `members` (the number of ScyllaDB nodes in that rack). Total node count is `racks × members`, and members should be equal across racks so token ownership stays balanced.

The same resource covers both development and production, the difference is the topology and the safety-related flags, not a different kind of manifest.

### Development: single rack, single node, `developerMode: true`

```yaml
apiVersion: scylla.scylladb.com/v1
kind: ScyllaCluster
metadata:
  name: scylla-dev
  namespace: scylla
spec:
  version: "2026.1.x"          # check operator.docs.scylladb.com for the current stable patch
  agentVersion: "3.x.x"
  developerMode: true          # relaxes production safety checks — never leave on outside dev
  datacenter:
    name: dev-dc
    racks:
      - name: rack-a
        members: 1             # a single node is fine for local evaluation
        storage:
          capacity: 10Gi
          storageClassName: scylladb-local-xfs
        resources:
          requests: { cpu: "1", memory: 1Gi }
          limits:   { cpu: "1", memory: 1Gi }
```

### Production: multiple racks across AZs, N members per rack

```yaml
apiVersion: scylla.scylladb.com/v1
kind: ScyllaCluster
metadata:
  name: scylla-prod
  namespace: scylla
spec:
  version: "2026.1.x"
  agentVersion: "3.x.x"
  developerMode: false
  automaticOrphanedNodeCleanup: true
  # scyllaConfig: scylladb-config   # optional ConfigMap for scylla.yaml tuning — see below
  datacenter:
    name: us-east-1
    racks:
      - name: us-east-1a            # one rack == one availability zone
        members: 3                  # N nodes in this rack/AZ; keep equal across racks
        storage:
          capacity: 1000Gi
          storageClassName: scylladb-local-xfs
        resources:                  # both blocks required for Guaranteed QoS — see below
          requests: { cpu: "6", memory: 50Gi }
          limits:   { cpu: "6", memory: 50Gi }
        agentResources:
          requests: { cpu: 100m, memory: 20Mi }
          limits:   { cpu: 100m, memory: 20Mi }
        placement: {}               # nodeAffinity + podAntiAffinity per rack — see below
      - name: us-east-1b
        members: 3
        # ...same storage / resources / agentResources; placement pinned to us-east-1b
      - name: us-east-1c
        members: 3
        # ...same storage / resources / agentResources; placement pinned to us-east-1c
```

This example is a 9-node cluster (3 racks × 3 members) spread across three AZs. The rack count should match your replication factor, and each rack's `placement` pins its pods to that rack's zone, both detailed in the sections below. Scale a rack by raising its `members`; add availability-zone fault tolerance by adding a rack. The `storage`, `resources`, `agentResources`, and `placement` blocks are shown once per rack for clarity above but must be present on **every** rack.

For a worked end-to-end example that templates this structure across dev and prod environments, see the `tluck/Scylla-K8s-Example` repository referenced in `SKILL.md` — treat it as one practitioner's tooling, not ScyllaDB's official interface.

## Custom `scylla.yaml` via `scyllaConfig`

A `ScyllaCluster` can reference a ConfigMap (via `scyllaConfig`) containing a `scylla.yaml`. Using it for application-level tuning, authenticator, authorizer, buffer sizes, compaction throughput, and similar settings, is the expected, correct usage and is required for any production deployment.

### Anti-Pattern: setting operator-managed fields in that ConfigMap

Within the same ConfigMap, networking, listen addresses, broadcast addresses, and seed nodes must **not** be set. The Operator manages these automatically based on the Kubernetes environment, and any conflicting value supplied manually is simply overridden. Setting them anyway doesn't cause an error, it just silently does nothing, which makes the mistake easy to miss during review.

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
- `scyllaArgs` and `sysctls`: `scyllaArgs` passes raw ScyllaDB command-line flags (e.g. `--smp` to cap shard count below the pinned core count), and `sysctls` sets kernel parameters the node needs for ScyllaDB (e.g. `fs.aio-max-nr` high enough for ScyllaDB's async I/O). Set these deliberately rather than copying values blindly, the right `--smp` depends on how many cores the pod actually pins.

## Scaling: Change `members`, Don't Recreate

Scaling a running cluster is an in-place edit to the `ScyllaCluster`, not a teardown. To grow a datacenter, raise a rack's `members`; the Operator adds nodes one at a time, streaming data to each before moving on. To add availability-zone fault tolerance, add a `rack` (matched to a new zone, and remember to provision the dedicated node pool for it first, see `node-preparation-and-storage.md`). Two things to keep in mind:

- **Scale racks evenly.** Uneven `members` across racks skews token ownership and undermines the zone-balanced availability the rack layout is for.
- **Removing nodes decommissions them.** Lowering `members` triggers a decommission that streams data off the departing node; it's not instantaneous, and `automaticOrphanedNodeCleanup: true` is what tidies up the Kubernetes-level leftovers afterward. Removing a whole rack should track your replication factor, dropping below RF racks reintroduces the single-zone-failure exposure the rack rule exists to prevent.

The operator's "Scale, add, remove racks" guide covers the node-operation details; the manifest change itself is just the `members`/`racks` edit.

## Multi-Datacenter: `externalSeeds` and a Shared Cluster Identity

A single `ScyllaCluster` is one datacenter. A multi-DC cluster is built by deploying a `ScyllaCluster` in each Kubernetes cluster/region and joining them, the field that joins them is `externalSeeds`: the reachable addresses of nodes in the *other* datacenter(s), which a new DC uses to bootstrap into the existing ring.

For the DCs to form one logical cluster rather than two separate ones:

- The `datacenter.name` must differ per DC (e.g. `dc1`, `dc2`), while the deployment shares one logical cluster identity.
- Cross-DC connectivity requires node addresses that are actually routable between clusters, this is where `exposeOptions` (`LoadBalancer` node services broadcasting `ServiceLoadBalancerIngress`, or a routable pod network) matters, see `client-access-and-networking.md`.
- TLS across DCs usually means **custom certificates** so both sides share a CA, rather than each cluster's auto-generated pair, see `security-tls-and-auth.md`.

```yaml
spec:
  externalSeeds:
    - <dc1-node-address>       # a reachable seed from the other datacenter
```

This is genuinely more involved than a single-DC deployment; treat the operator's dedicated multi-datacenter guide as the authoritative procedure and this section as the map of which fields are involved.

## Tablets Change How Racks and Repair Behave

Recent ScyllaDB defaults to **tablets** (dynamic, per-table data distribution) rather than the older static vnode token ranges. Two practical consequences on Kubernetes:

- **Rack/RF validation.** Tablet-based keyspaces enforce that replicas are spread across the declared racks, which is why deployments sometimes expose overrides (the example repo's `rf_validate_rack_keyspaces` / `enforce_rack_list`). Prefer fixing the rack layout to match RF (see the rack rule above) over disabling the validation, the check is enforcing exactly the availability property the rack layout is meant to provide.
- **Repair.** Tablet clusters use tablet-aware repair; scheduled repair is still driven through ScyllaDB Manager (see `monitoring-and-operations.md`), but the unit of repair is the tablet rather than a vnode range.
