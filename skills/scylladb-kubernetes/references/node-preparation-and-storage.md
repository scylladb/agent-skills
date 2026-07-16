---
title: Node Preparation and Storage
impact: CRITICAL
impactDescription: Getting CPU pinning or storage wrong at the node level silently degrades every ScyllaDB pod's performance, and is much harder to fix after the cluster is running
tags: kubernetes, node-preparation, cpu-manager, xfs, storage, nodeconfig
---

## CPU Manager: Static Policy Is Required for Real Performance

By default, kubelet uses CFS quota to enforce CPU limits, which lets a pod's threads move between cores as load changes. ScyllaDB's shard-per-core architecture depends on threads staying pinned to specific cores; without that, ScyllaDB pods lose the low-latency benefit the architecture is built around. Kubelet must be configured with `cpuManagerPolicy: static` on any node pool that will run ScyllaDB.

This is platform-specific to configure:

**GKE** (node system configuration):
```yaml
kubeletConfig:
  cpuManagerPolicy: static
```

**EKS** (eksctl node group config):
```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
# ...
nodeGroups:
  - name: scylla-pool
    kubeletExtraConfig:
      cpuManagerPolicy: static
```

**OpenShift**: via a `KubeletConfig` resource targeting the `MachineConfigPool` dedicated to ScyllaDB nodes, following Red Hat's own "Setting up CPU Manager" documentation.

**OKE** (Oracle Container Engine for Kubernetes) is also covered by the Operator's install guides; the same static-CPU-policy requirement applies, configured through OKE's node-pool kubelet settings.

### The QoS Requirement Nobody Notices Until It's Wrong

Static CPU policy alone isn't enough. Only Pods in the **Guaranteed QoS class** are eligible for CPU pinning, and Guaranteed QoS requires `resources.requests` and `resources.limits` to be set to the **same value**. A ScyllaCluster manifest with mismatched requests/limits will run, and will look fine at a glance, it just silently won't get pinned cores, and the performance loss isn't obviously connected to that cause unless someone checks.

## Dedicated Node Pool: One ScyllaDB Pod Per Node

The production model is one ScyllaDB pod per Kubernetes node, so that pod owns the node's entire set of pinnable cores rather than sharing them. This is what turns the static CPU policy and Guaranteed QoS above into *actual* exclusive pinning, if two ScyllaDB pods, or a ScyllaDB pod and some other workload, share a node they contend for the same cores and the shard-per-core benefit is lost. Three things have to line up:

1. **A node pool dedicated to ScyllaDB.** Taint the pool so nothing else schedules onto it, and label it so the Operator's affinity rules can find it:
   ```
   taint:  scylla-operator.scylladb.com/dedicated=scyllaclusters:NoSchedule
   label:  scylla.scylladb.com/node-type=scylla
   ```
   The ScyllaCluster's `placement` carries the matching toleration and `nodeAffinity` (see `scyllacluster-configuration.md`).

2. **One pod per node.** `podAntiAffinity` keyed on `kubernetes.io/hostname` in the ScyllaCluster keeps two pods of the same cluster off the same node (see `scyllacluster-configuration.md`). Combined with the dedicated pool, each node then runs exactly one ScyllaDB pod.

3. **A machine type sized to one ScyllaDB node.** Choose the instance type so a single pod's integer CPU request, with `requests == limits` for Guaranteed QoS, consumes the node's allocatable cores minus headroom for kubelet/system daemons and the Manager Agent sidecar (`agentResources`). Don't request 100% of the node, leave a small reservation or the Guaranteed pod won't schedule at all.

Because of (2), the number of `members` in a rack equals the number of nodes in that rack's zone, size the dedicated node pool per zone accordingly (`racks × members` nodes total).

### Separate Node Pools for the Supporting Stack and Applications

The dedicated ScyllaDB pool is for the data nodes only. The rest of the stack, the Operator control plane (`scylla-operator` namespace), ScyllaDB Monitoring (Prometheus/Grafana), the ScyllaDB Manager *server*, and any user applications, belongs on separate, general-purpose node pools with right-sized VM instances. None of those workloads need local NVMe or pinned cores, and provisioning them on the expensive, high-spec ScyllaDB instances wastes exactly the capacity you dedicated to ScyllaDB. The ScyllaDB pool's `NoSchedule` taint already repels anything without the matching toleration, so these workloads naturally land on the general pool.

The one exception is the Manager *Agent*, which is a sidecar inside every ScyllaDB pod and therefore always runs on the ScyllaDB nodes, that's what `agentResources` sizes. Only the Manager server component runs on the general pool (see `monitoring-and-operations.md`). The net effect: the pinned, NVMe-backed instances do nothing but serve ScyllaDB, and the general pool can be sized for cost rather than for ScyllaDB's performance requirements.

## Storage: XFS Is a Hard Requirement, Not a Recommendation

ScyllaDB requires storage formatted with XFS. This isn't a tuning suggestion, it won't run correctly on other filesystems. `xfsprogs` must be installed on any node that ScyllaDB's `NodeConfig` controller will format.

### Local NVMe vs Network-Attached Storage

Both work, but they are not equivalent for production:

- **Local NVMe storage** is the recommended choice for production. It's provisioned via the ScyllaDB Local CSI Driver, a privileged DaemonSet that runs on every ScyllaDB node.
- **Network-attached storage** (e.g. `pd-ssd` on GKE, `gp3` on EKS) is acceptable for development and evaluation, but adds latency to every I/O operation and is explicitly not recommended for latency-sensitive production workloads. If used, set `storageClassName` to the cloud platform's own class directly, no `NodeConfig` or Local CSI Driver is needed in that case.

### What NodeConfig Actually Automates

When a Kubernetes node has local disks attached, the platform typically mounts them but does neither RAID configuration nor filesystem formatting. The `NodeConfig` custom resource automates this: it can create a RAID0 array from multiple NVMe devices, format it with XFS, mount it (typically at `/var/lib/persistent-volumes`), and apply the `prjquota` mount option the Local CSI Driver needs for per-volume quota enforcement.

Storage capacity is shared across all volumes on a given node, the Local CSI Driver uses XFS project quotas to enforce individual PVC size limits, but total capacity is still bounded by the underlying physical disk.

## Node Labeling Convention

ScyllaDB Operator's installation guides assume nodes intended to run ScyllaClusters carry the label:

```
scylla.scylladb.com/node-type=scylla
```

This label is what `nodeAffinity` rules in a ScyllaCluster manifest select on, paired with a matching toleration for the `scylla-operator.scylladb.com/dedicated` taint. Get this label wrong or omit it and ScyllaDB pods either won't schedule onto the dedicated nodes at all, or will compete with other workloads for the same nodes, defeating the point of dedicating them.
