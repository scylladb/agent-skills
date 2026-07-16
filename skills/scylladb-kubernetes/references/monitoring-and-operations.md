---
title: Monitoring and Operations
impact: HIGH
impactDescription: Skipping monitoring or assuming Manager needs a separate install both lead to running a cluster with no visibility into its own health
tags: kubernetes, monitoring, scylla-manager, backup, repair, grafana, prometheus
---

## Always Install ScyllaDB Monitoring

ScyllaDB's own guidance is direct on this point: install ScyllaDB Monitoring alongside every cluster, not just for troubleshooting after something goes wrong. It's the only practical way to see per-node and per-shard behavior, transactions per CPU, cache hit rates, I/O and network bottlenecks, that a `kubectl get pods` or generic cluster dashboard won't show. ScyllaDB's own monitoring solution is built on Prometheus and Grafana, deployed via Helm charts, with the ScyllaDB nodes annotated so Prometheus can scrape them automatically.

A common setup pattern (seen both in ScyllaDB's own guides and in community deployment scripts) is to install a general-purpose Prometheus stack (e.g. `kube-prometheus-stack`) for cluster-wide monitoring, but **remove its bundled Grafana deployment** so that ScyllaDB's own Monitoring custom resource can own the Grafana instance and its ScyllaDB-specific dashboards, rather than the two fighting over the same Grafana install.

## ScyllaDB Manager Is Already Running, Don't Look for a Separate Install

ScyllaDB Manager, which handles scheduled backups and repairs, is integrated with the Operator: every ScyllaDB pod already includes a ScyllaDB Manager Agent container as a sidecar (this is the `agentResources` block referenced in `scyllacluster-configuration.md`). A user asking "how do I install Scylla Manager" on a Kubernetes deployment usually needs the Manager **server** component deployed (its own Helm chart, `scylla-manager`), the per-node agent side is already there once the ScyllaCluster is running.

## What to Check Beyond "Is It Running"

Beyond confirming pods are `Running`, the things worth actually verifying on a new deployment:

- **Datacenter and rack configuration** actually matches the intended replication factor and zone spread (see `scyllacluster-configuration.md`), a cluster can be "up" while still being misconfigured for the availability it's meant to provide.
- **CPU pinning took effect** — confirm the pods actually landed in Guaranteed QoS class, not just that `cpuManagerPolicy: static` is set on the nodes; a resources/agentResources mismatch (see `scyllacluster-configuration.md`) silently prevents pinning even with the node-level policy correctly configured.
- **I/O settings** are appropriate for the actual disks in use, particularly relevant if network-attached storage was used instead of local NVMe (see `node-preparation-and-storage.md`), since the performance profile differs meaningfully between the two.

## Backup and Repair, at a Glance

Once ScyllaDB Manager's server is deployed and a cluster registered with it, both backups and repairs are managed through `sctool` (Manager's CLI) or the equivalent custom resources, rather than manual ScyllaDB-side commands. Typical operations:

```bash
# One-off backup
sctool backup -c <cluster> -L s3:<bucket-name>

# Scheduled backup
sctool backup --name="hourly_backup" --cluster="<cluster>" \
  --location="s3:<bucket-name>" --cron="@hourly" --retention=24
```

Object storage location (`s3:`, `gcs:`) needs to be reachable from the Manager Agent sidecars, this is a networking/credentials concern to confirm before assuming a backup schedule is actually working, a misconfigured location can fail silently until someone checks whether backups actually landed in the bucket.

## Object Storage Setup Is a Prerequisite, Not an Afterthought

Before `sctool backup` will work, the Manager Agent sidecars need both network reachability *and* credentials for the bucket, and how you supply credentials depends on the backend:

- **AWS S3** — either static keys provided to the agent, or (preferably) an IAM role attached to the ScyllaDB node pool so no long-lived keys live in the cluster.
- **GCS** — on GKE, Workload Identity is the clean path: bind the ScyllaDB pods' Kubernetes service account to a GCP service account that can write the bucket, rather than mounting a JSON key.
- **MinIO** — a self-hosted, S3-compatible option useful for on-prem or for evaluating the backup path without a cloud account. It's addressed with an `s3:` location pointing at the MinIO endpoint plus its access/secret keys. (The example repo automates a MinIO deployment via `deployMinio.bash` for exactly this local-testing case.)

Whichever backend, verify a backup actually lands (`sctool` task status plus an object listing in the bucket) rather than trusting that a scheduled task was created, credential/endpoint mistakes surface only at run time.

## Restore Is Its Own Procedure

Restore is not the inverse of `sctool backup` in one command, it's a deliberate multi-step operation and worth rehearsing before you need it. The shape of it: identify the snapshot to restore (from `sctool backup list` against the backup location), restore the schema, then restore the data into a cluster whose topology is compatible with the backup. ScyllaDB Manager drives this, and the Operator docs' "Restore from backup" guide is the authoritative step-by-step, don't improvise a restore from memory during an incident. The two things people get wrong: assuming restore auto-discovers the latest snapshot (you select it explicitly), and restoring into a topology that doesn't match what was backed up.
