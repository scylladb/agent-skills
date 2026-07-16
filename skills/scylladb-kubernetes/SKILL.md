---
name: scylladb-kubernetes
description: Guide users deploying and operating ScyllaDB on Kubernetes via the official ScyllaDB Operator. Use this skill when a user is setting up a ScyllaCluster, configuring node storage/CPU pinning for ScyllaDB pods, installing the Operator, or troubleshooting a Kubernetes-based ScyllaDB deployment. Triggers on "ScyllaDB Operator", "ScyllaCluster", "scylla-operator", "ScyllaDB on Kubernetes", "ScyllaDB Helm chart", "NodeConfig", "ScyllaDB EKS", "ScyllaDB GKE", "ScyllaDB kubernetes deployment".
---

# ScyllaDB on Kubernetes (ScyllaDB Operator)

ScyllaDB Operator is the official Kubernetes Operator for deploying and managing ScyllaDB clusters. It introduces custom resources, most importantly `ScyllaCluster`, that let Kubernetes manage ScyllaDB the way it manages any other workload, while still respecting ScyllaDB's own requirements around CPU pinning, local NVMe storage, and rack/zone topology.

This skill covers the official Operator model (the `ScyllaCluster`, `NodeConfig`, and `ScyllaOperatorConfig` custom resources, installed via Helm or GitOps manifests). It does not teach any one team's custom deployment scripts, several exist in the community, including a detailed sed-templated bash pipeline in the `tluck/Scylla-K8s-Example` repository, and those are useful references for a working end-to-end example, but they are one practitioner's tooling choices, not ScyllaDB's own documented interface. When a user's question is about the underlying Operator resources and requirements, ground the answer in this skill; when it's specifically about someone else's deployment scripts, say so explicitly rather than presenting their conventions as official.

## When to Use This Skill

- The user is deploying ScyllaDB on Kubernetes for the first time (EKS, GKE, OpenShift, or generic)
- The user is writing or reviewing a `ScyllaCluster` manifest
- The user is configuring node-level prerequisites: CPU manager policy, local storage, node labels
- The user is troubleshooting a ScyllaDB Operator installation, upgrade, or a ScyllaCluster that won't reach Available
- The user references ScyllaDB Manager running inside Kubernetes (it ships as a sidecar container in each ScyllaDB pod, not a separate install)

For schema design once the cluster is running, defer to `scylladb-data-modeling`. For DynamoDB-API access, defer to `scylladb-alternator`, Alternator can be enabled on a Kubernetes-deployed cluster the same as anywhere else.

## Quick Reference

### Reference Files — 4

- [node-preparation-and-storage](references/node-preparation-and-storage.md) — CPU manager static policy, Guaranteed QoS requirement, XFS/local NVMe storage via NodeConfig and the Local CSI Driver, and the node-labeling convention the Operator expects. Consult before provisioning the underlying Kubernetes nodes, this has to be right before a ScyllaCluster is even created.
- [scyllacluster-configuration](references/scyllacluster-configuration.md) — The ScyllaCluster resource itself: what not to override in `scyllaConfig`, the rack-to-replication-factor rule, pod anti-affinity and node affinity/tolerations, and the `resources` vs `agentResources` split. Consult when writing or reviewing a ScyllaCluster manifest.
- [installation-and-upgrades](references/installation-and-upgrades.md) — cert-manager as a real dependency, Helm vs GitOps installation trade-offs (including a real CRD-management gap in the Helm path), and a known current EKS-specific Operator bug with its workaround. Consult before installing or upgrading the Operator itself.
- [monitoring-and-operations](references/monitoring-and-operations.md) — Why ScyllaDB Monitoring should always be installed alongside a cluster, and how ScyllaDB Manager already ships inside every ScyllaDB pod rather than needing a separate install. Consult when a user asks about observability or backup/repair automation.

## Version Note

ScyllaDB's own documentation pages currently reference slightly different patch versions of ScyllaDB (2026.1.0 through 2026.1.3) and the Manager Agent (3.9.0 vs 3.10.1) across different guides, which appears to be a documentation sync gap rather than a single authoritative number. Don't hardcode a specific patch version into a deliverable without checking `https://operator.docs.scylladb.com` for the current stable release first.
