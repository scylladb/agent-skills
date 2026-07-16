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
