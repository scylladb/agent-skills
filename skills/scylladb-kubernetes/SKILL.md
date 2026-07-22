---
name: scylladb-kubernetes
description: Guide users deploying and operating ScyllaDB on Kubernetes via the official ScyllaDB Operator. Use this skill when a user is setting up a ScyllaCluster, configuring node storage/CPU pinning for ScyllaDB pods, installing the Operator, or troubleshooting a Kubernetes-based ScyllaDB deployment. Triggers on "ScyllaDB Operator", "ScyllaCluster", "scylla-operator", "ScyllaDB on Kubernetes", "ScyllaDB Helm chart", "NodeConfig", "ScyllaDB EKS", "ScyllaDB GKE", "ScyllaDB OKE", "ScyllaDB kubernetes deployment", "exposeOptions", "ScyllaCluster TLS/mTLS", "ScyllaDB Manager backup/restore on Kubernetes", "multi-datacenter ScyllaDB", "externalSeeds".
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
- The user's application can't reach the cluster, or they're planning external/cross-datacenter client access (`exposeOptions`, load balancers, broadcast addresses)
- The user is securing a cluster: authentication, the default superuser, TLS/mTLS encryption, or extracting client certificates
- The user is scaling, adding/removing racks, or building a multi-datacenter cluster with `externalSeeds`

For schema design once the cluster is running, defer to `scylladb-data-modeling`. For DynamoDB-API access, defer to `scylladb-alternator`, Alternator can be enabled on a Kubernetes-deployed cluster the same as anywhere else.

## Quick Reference

### Reference Files — 6

- [node-preparation-and-storage](references/node-preparation-and-storage.md) — CPU manager static policy, Guaranteed QoS requirement, the dedicated ScyllaDB node pool plus separate general-purpose pools for the Operator/monitoring/manager/apps, XFS/local NVMe storage via NodeConfig and the Local CSI Driver, and the node-labeling convention the Operator expects. Consult before provisioning the underlying Kubernetes nodes, this has to be right before a ScyllaCluster is even created.
- [scyllacluster-configuration](references/scyllacluster-configuration.md) — The ScyllaCluster resource itself: a complete `datacenter → racks → members` template contrasting a dev (single-node) and production (multi-rack, multi-AZ, N members per rack) layout, custom `scylla.yaml` via `scyllaConfig` and what not to override in it, the rack-to-replication-factor rule, pod anti-affinity and node affinity/tolerations, and the `resources` vs `agentResources` split. Consult when writing or reviewing a ScyllaCluster manifest.
- [installation-and-upgrades](references/installation-and-upgrades.md) — cert-manager as a real dependency, Helm vs GitOps installation trade-offs (including a real CRD-management gap in the Helm path), provisioning a dedicated ScyllaDB node pool (taint/label/machine-sizing) so the one-pod-per-node CPU-pinning model actually holds, and a known current EKS-specific Operator bug with its workaround. Consult before installing or upgrading the Operator itself.
- [monitoring-and-operations](references/monitoring-and-operations.md) — Why ScyllaDB Monitoring should always be installed alongside a cluster, how ScyllaDB Manager already ships inside every ScyllaDB pod rather than needing a separate install, object-storage/credentials setup (S3/GCS/MinIO) for backups, and that restore is its own deliberate procedure. Consult when a user asks about observability or backup/repair/restore automation.
- [client-access-and-networking](references/client-access-and-networking.md) — `exposeOptions`: the per-node Service (`nodeService.type`: Headless/ClusterIP/LoadBalancer) and the broadcast address (`broadcastOptions.clients`/`nodes`: PodIP/ServiceClusterIP/ServiceLoadBalancerIngress), how to match them for in-cluster vs external vs multi-DC access, and the CQL/Alternator ports. Consult when an application can't reach the cluster or you're planning external/cross-DC connectivity.
- [security-tls-and-auth](references/security-tls-and-auth.md) — Changing the default `cassandra` superuser, enabling password auth, the Operator's auto-generated TLS (serving CA, admin client cert, connection bundle) for client-to-node and node-to-node encryption, extracting certs for clients, mTLS as an auth mechanism, and when custom certs are needed (multi-DC). Consult for any deployment that has to be secured.

## Version Note

ScyllaDB's own documentation pages currently reference slightly different patch versions of ScyllaDB (2026.1.0 through 2026.1.3) and the Manager Agent (3.9.0 vs 3.10.1) across different guides, which appears to be a documentation sync gap rather than a single authoritative number. Don't hardcode a specific patch version into a deliverable without checking `https://operator.docs.scylladb.com` for the current stable release first.
