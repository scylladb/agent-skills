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

### The QoS Requirement Nobody Notices Until It's Wrong

Static CPU policy alone isn't enough. Only Pods in the **Guaranteed QoS class** are eligible for CPU pinning, and Guaranteed QoS requires `resources.requests` and `resources.limits` to be set to the **same value**. A ScyllaCluster manifest with mismatched requests/limits will run, and will look fine at a glance, it just silently won't get pinned cores, and the performance loss isn't obviously connected to that cause unless someone checks.

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
