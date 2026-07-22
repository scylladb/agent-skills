---
title: Installation and Upgrades
impact: HIGH
impactDescription: The Helm install path has a real, documented CRD-management gap, and there is a currently-known EKS-specific Operator bug with an easy but non-obvious workaround
tags: kubernetes, installation, helm, gitops, cert-manager, upgrades, eks
---

## cert-manager Is a Real Dependency, Not Optional Tooling

ScyllaDB Operator's webhook server needs a TLS certificate, and cert-manager is what provisions it. If cert-manager is already installed in the cluster for other reasons, this step can be skipped, the Operator will use it. If not, ScyllaDB provides a bundled manifest to install it:

```bash
kubectl apply --server-side -f=https://raw.githubusercontent.com/scylladb/scylla-operator/v1.21/examples/third-party/cert-manager.yaml
```

(Check the version segment in that URL against the Operator version actually being installed, it's pinned to a release branch.) Alternatively, follow cert-manager's own upstream installation instructions directly.

If a custom webhook certificate is preferred instead of cert-manager, set `webhook.createSelfSignedCertificate: false` and provide `webhook.certificateSecretName` when installing the Operator's Helm chart.

## Helm vs GitOps: A Real Trade-off, Not Just Style Preference

Two installation paths exist, and the choice isn't cosmetic:

- **Helm** is simpler to get started with, but only supports **single-datacenter** deployments, and, more importantly, **Helm does not manage CustomResourceDefinition updates**. It creates CRDs on first install and never updates them again. Every subsequent Operator upgrade requires manually reapplying the CRDs from the new chart version:
  ```bash
  tmpdir=$(mktemp -d)
  helm pull scylla-operator/scylla-operator --version <version> --untar --untardir "${tmpdir}"
  find "${tmpdir}/scylla-operator/crds/" -name '*.yaml' -printf '-f=%p ' | xargs kubectl apply
  ```
  Skipping this step after an upgrade is a real, easy-to-hit failure mode, the Operator pods will be running a newer version while the CRDs it depends on are stale.
- **GitOps (raw manifests via `kubectl`)** supports multi-datacenter deployments and gives a more consistent experience across upgrades, since CRD management isn't a separate manual step tied to Helm's limitations.

For anything beyond a single-DC quick evaluation, or anywhere upgrades will happen more than once, GitOps is the more defensible recommendation. Helm is fine for a fast first deployment, but say so explicitly rather than letting a user assume it's the production-grade default.

## Namespace Convention

ScyllaDB Operator itself must run in the `scylla-operator` namespace. Running the ScyllaDB cluster itself in a namespace separate from other applications is called out as a best practice (not strictly enforced), for the same reasons any stateful, resource-sensitive workload benefits from namespace isolation.

## Cleanup After Uninstall

`helm uninstall` does not remove CRDs. A full cleanup requires deleting them explicitly:

```bash
kubectl delete crd \
  scyllaclusters.scylla.scylladb.com \
  nodeconfigs.scylla.scylladb.com \
  scyllaoperatorconfigs.scylla.scylladb.com \
  scylladbmonitorings.scylla.scylladb.com
```

Deleting these while a ScyllaCluster still exists will affect that cluster's data, this is cleanup for a full teardown, not a routine step.

### When a Teardown Gets Stuck: Finalizers

A common, confusing failure during teardown is a resource that won't delete, a namespace stuck `Terminating`, a `PersistentVolume` that won't release, or a CRD that lingers. The usual cause is a **finalizer**: a metadata entry that blocks deletion until a controller does its cleanup, and if that controller is already gone (e.g. the Operator was uninstalled first), nothing ever clears it and the resource hangs indefinitely.

The order matters: delete `ScyllaCluster` resources *before* removing the Operator, so the Operator is still around to run its finalizers. When something is already stuck, the fix is to inspect and, as a last resort, clear the offending finalizer:

```bash
kubectl get namespace <ns> -o jsonpath='{.spec.finalizers}'   # inspect first
kubectl patch <kind>/<name> -n <ns> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

Force-clearing a finalizer skips the cleanup it was guarding, so only do it on a genuine teardown where you've accepted the resource (and its data, for a PV) is going away. The example repo's `remove_stuck_namespace.bash`, `remove_stuck_pv.bash`, and `remove_stuck_crds.bash` automate exactly this pattern, they're teardown recovery tools, not routine operations.

## Provision a Dedicated Node Pool Before Creating the Cluster

Installing the Operator is not enough on its own, the production deployment model is one ScyllaDB pod per Kubernetes node so that each pod owns the node's full set of pinnable cores. That only holds if the node pool is provisioned for it at install time, and it's easy to skip because the Operator will happily schedule a cluster onto shared nodes and appear healthy while quietly losing CPU pinning. Set this up as part of installation:

1. **Create a node pool dedicated to ScyllaDB**, with kubelet `cpuManagerPolicy: static` (see `node-preparation-and-storage.md`), then taint and label it so only ScyllaDB pods land there:
   ```
   taint:  scylla-operator.scylladb.com/dedicated=scyllaclusters:NoSchedule
   label:  scylla.scylladb.com/node-type=scylla
   ```

2. **Size the machine type to one ScyllaDB node.** The pod's integer CPU request, with `requests == limits` for Guaranteed QoS, should consume the node's allocatable cores minus headroom for kubelet/system daemons and the Manager Agent sidecar (`agentResources`). Requesting 100% of the node leaves nothing for system overhead and the Guaranteed pod won't schedule.

3. **Enforce one pod per node** via `podAntiAffinity` on `kubernetes.io/hostname` in the ScyllaCluster manifest, combined with the dedicated pool, each node runs exactly one ScyllaDB pod.

Provision **separate, general-purpose node pool(s)** for everything that is not a ScyllaDB data node: the Operator control plane (`scylla-operator` namespace), ScyllaDB Monitoring (Prometheus/Grafana), the ScyllaDB Manager *server*, and any user applications. These don't need local NVMe or pinned cores, and the ScyllaDB pool's `NoSchedule` taint already keeps them off the data nodes, so they land on the general pool automatically, size it for cost rather than for ScyllaDB's performance requirements. (The Manager *Agent* is a sidecar inside each ScyllaDB pod and stays on the ScyllaDB nodes regardless, see `monitoring-and-operations.md`.)

The mechanics of each of these (CPU manager, QoS, taints/labels, anti-affinity, and machine sizing) are covered in `node-preparation-and-storage.md` and `scyllacluster-configuration.md`, this is the checklist to run through before a production `ScyllaCluster` is created, not after.

## Known Current Bug: EKS Node Tuning and `systemctl`

As of ScyllaDB's own documentation (dated May 2026), the default ScyllaDB utils image used by the Operator for node-tuning jobs contains a broken `systemctl` binary that fails on EKS nodes running `irqbalance`. The documented workaround is to override the utils image via `ScyllaOperatorConfig`:

```yaml
apiVersion: scylla.scylladb.com/v1alpha1
kind: ScyllaOperatorConfig
metadata:
  name: cluster
spec:
  scyllaUtilsImage: "docker.io/scylladb/scylla:2025.1"
```

This is worth flagging as a live, current gotcha rather than historical trivia, it was still listed as unfixed upstream as of the documentation checked for this file. If deploying on EKS and node-tuning jobs are failing in a way that traces back to `systemctl`, this is the known cause and fix, check ScyllaDB's current documentation to see whether it has since been resolved before assuming it's still needed.
