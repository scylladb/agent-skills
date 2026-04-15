---
title: ScyllaDB Cloud Connection Details
tags: cloud, connection, credentials, IP allowlist, VPC peering
---

# ScyllaDB Cloud Connection Details

## Connection Parameters

Every ScyllaDB Cloud connection requires the following:

| Parameter | Source | Example |
|-----------|--------|---------|
| Contact points (node addresses) | Cloud Console → Connect tab | `node-0.abc123.cloud.scylladb.com` |
| Port | Fixed | `9042` |
| Username | Cloud Console → Connect tab | `scylla` |
| Password | Cloud Console → Connect tab | (generated) |
| Datacenter name | Cloud Console → Connect tab | `AWS_US_EAST_1` |

## IP Allowlisting

Before connecting, the client's public IP address must be added to the cluster's **Allowed IPs** list:

1. Go to **My Clusters** → select your cluster
2. Open the **Security** tab → **Allowed IPs**
3. Add your IP address or CIDR range

For production, prefer VPC Peering over IP allowlisting.

## VPC Peering

VPC Peering routes traffic over a private network instead of the public internet:

- Must be enabled **at cluster creation time** — cannot be added later
- Eliminates the need for IP allowlisting
- Supports AWS VPC Peering and GCP VPC Peering
- Configuration guides: [AWS](https://cloud.docs.scylladb.com/stable/cluster-connections/aws-vpc-peering.html) | [GCP](https://cloud.docs.scylladb.com/stable/cluster-connections/gcp-vpc-peering.html)

## Datacenter Naming Convention

ScyllaDB Cloud datacenter names follow the pattern `{PROVIDER}_{REGION}` with underscores:

| Cloud Provider | Region | Datacenter Name |
|---------------|--------|-----------------|
| AWS | us-east-1 | `AWS_US_EAST_1` |
| AWS | eu-west-1 | `AWS_EU_WEST_1` |
| GCP | us-east1 | `GCP_US_EAST1` |
| GCP | europe-west1 | `GCP_EUROPE_WEST1` |

The exact datacenter name is shown on the cluster's **Connect** tab. Always copy it from there — do not guess.

## Common Connection Errors

| Error | Cause | Fix |
|-------|-------|-----|
| Connection refused | IP not in Allowed IPs | Add client IP to Allowed IPs |
| Authentication failed | Wrong username/password | Verify credentials on Connect tab |
| No hosts available | Wrong contact points or DC name | Check node addresses and DC name on Connect tab |
