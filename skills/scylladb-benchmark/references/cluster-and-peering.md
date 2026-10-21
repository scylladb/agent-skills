---
title: Benchmark cluster and VPC peering through the Cloud API
tags: cloud api, api token, x cloud, scaling, instanceTypeIDs, availabilityZoneIdsOverride, cluster-preview, pricing, broadcastType, private, cidrBlock, vpc peering, allowCql, firewall, credentials
---

# Benchmark cluster and VPC peering through the Cloud API

These calls use the ScyllaDB Cloud REST API at `https://api.cloud.scylladb.com` ([OpenAPI spec](https://cloud.docs.scylladb.com/stable/_static/swagger.json)). The Cloud MCP server has no VPC peering tool ([MCP docs](https://cloud.docs.scylladb.com/stable/api-docs/mcp.md)), so use the REST API for the full flow.

Contents: [API token](#get-the-api-token), [IDs and prices](#look-up-ids-and-prices), [create](#create-the-cluster), [nodes and credentials](#read-the-nodes-and-the-credentials), [peering](#peer-the-loader-vpc), [options](#options), [delete](#delete-the-peering-and-the-cluster).

## Get the API token

Tell the user to do these steps. Do not ask for the token in the chat. The chat transcript keeps it.

1. Create a personal token in **Settings > Personal Tokens** ([create a token](https://cloud.docs.scylladb.com/stable/api-docs/create-api-token.md)). Set a short expiration, for example 1 day. The default is *Never*.
2. Give the token to the agent in one of these ways:
   - Before you start the agent, run `export SCYLLADB_CLOUD_API_TOKEN=<token>`.
   - If the agent runs already, add `.env` to `.gitignore`. Then write `SCYLLADB_CLOUD_API_TOKEN=<token>` in `.env` in the project root.
3. Revoke the token in **Settings > Personal Tokens** after the cleanup.

If the user pastes the token in the chat, tell the user to revoke it and create a new one. For other rules to keep the token out of git, use the `scylladb-cloud-mcp` skill.

Check the token without printing it. A `200` means that the token works:

```sh
[ -f .env ] && { set -a; . ./.env; set +a; }
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $SCYLLADB_CLOUD_API_TOKEN" \
  https://api.cloud.scylladb.com/account/default
```

Shell variables can be lost between commands. Load `.env` again in each command that calls the API.

## Look up IDs and prices

```sh
[ -f .env ] && { set -a; . ./.env; set +a; }
API=https://api.cloud.scylladb.com
AUTH="Authorization: Bearer $SCYLLADB_CLOUD_API_TOKEN"
RUN_ID=bench-$(date -u +%Y%m%d%H%M)        # names and tags every resource of this test
REGION=us-east-1; TYPE=i4i.2xlarge
ACCOUNT_ID=$(curl -s -H "$AUTH" "$API/account/default" | jq -r .data.accountId)
REGION_ID=$(curl -s -H "$AUTH" "$API/deployment/cloud-provider/1/regions" \
  | jq -r ".data.regions[] | select(.externalId == \"$REGION\") | .id")       # AWS is provider 1
read VERSION_ID SCYLLA_VERSION < <(curl -s -H "$AUTH" "$API/deployment/scylla-versions" | jq -r '[.data.scyllaVersions[]
  | select(.newCluster == "ENABLED" and (.version | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")))]
  | max_by(.version | split(".") | map(tonumber)) | "\(.id) \(.version)"')   # most recent release
curl -s -H "$AUTH" "$API/deployment/cloud-provider/1/region/$REGION_ID" > instances.json
TYPE_ID=$(jq -r ".data.instances[] | select(.externalId == \"$TYPE\") | .id" instances.json)
VCPU_MIN=$((3 * $(jq -r ".data.instances[] | select(.externalId == \"$TYPE\") | .cpuCount" instances.json)))
jq -r '.data.instances[] | select(.freeTier) | [.id, .externalId, .cpuCount, .memory] | @tsv' instances.json
```

The last command lists the types that the free trial allows (`freeTier: true`). The default shape uses the largest. Get the on-demand price for one node-hour:

```sh
curl -s -X POST -H "$AUTH" -H 'content-type: application/json' "$API/pricing" --data \
  "{\"infrastructure\":{\"provider\":\"AWS\",\"region\":\"$REGION\",\"deployment\":\"Cloud\",\"instanceType\":\"$TYPE\"},
    \"product\":{\"productTypes\":[\"XCLOUD\"]},\"commercial\":{\"contractType\":\"ON_DEMAND\"}}" \
  | jq -r '.items[0].pricing.estimates[] | select(.intervalCode == "PT1H") | .totalAmount'
```

Multiply by the node count. Show the user the hourly cost of the cluster and the loaders. Say that the cost continues until the resources are deleted. For the default recipe, give the time from the Timing row in [SKILL.md](../SKILL.md#default-recipe-fast-path). Wait for approval.

## Create the cluster

X Cloud scales on storage use, and the API has no switch to turn scaling off ([autoscaling](https://cloud.docs.scylladb.com/stable/cloud-setup/autoscaling-behavior.md)). Pin the shape: allow one instance type (`instanceTypeIDs`), and set `vcpu.min` to the vCPU total of the shape. The cluster does not scale below the minimums ([scaling policy](https://cloud.docs.scylladb.com/stable/cloud-setup/create-clusters.md)).

Select 3 AZ IDs where the loader type is available. Pass them in `availabilityZoneIdsOverride`, so you can create the loaders at the same time as the cluster. The `cidrBlock` must be an allowed range that does not overlap the loader VPC ([VPC peering](https://cloud.docs.scylladb.com/stable/cluster-connections/vpc-peering/aws-vpc-peering.md)).

```sh
curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cloud-account" | jq -c '.data[] | select(.owner == "Scylla") | {id, cloudProviderId}'
curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cloud-account/<id>/region/$REGION_ID/zones" | jq -r '.data[].id'
aws ec2 describe-instance-type-offerings --region $REGION --location-type availability-zone-id \
  --filters Name=instance-type,Values=c7i.8xlarge --query 'InstanceTypeOfferings[].Location' --output text
AZS="use1-az1 use1-az2 use1-az4"                  # 3 AZ IDs that are in both lists
AZ_IDS=$(printf '"%s",' $AZS); AZ_IDS=${AZ_IDS%,}
CLUSTER_CIDR=10.201.0.0/24
cat > cluster.json <<EOF
{"clusterName":"$RUN_ID","cloudProviderId":1,"regionId":$REGION_ID,"scyllaVersionId":$VERSION_ID,
 "replicationFactor":3,"userApiInterface":"CQL","broadcastType":"PRIVATE","cidrBlock":"$CLUSTER_CIDR",
 "enableDnsAssociation":true,"tablets":"enforced","encryptionAtRest":{"provider":"scylla-aws"},
 "availabilityZoneIdsOverride":[$AZ_IDS],"placement":"","freeTier":false,"jumpStart":false,"promProxy":false,
 "scaling":{"mode":"xcloud","instanceFamilies":[],"instanceTypeIDs":[$TYPE_ID],
   "policies":{"storage":{"targetUtilization":0.9},"vcpu":{"min":$VCPU_MIN}}}}
EOF
curl -s -X POST -H "$AUTH" -H 'content-type: application/json' "$API/account/$ACCOUNT_ID/cluster-preview" \
  --data @cluster.json | jq -c '[.data.DCs[].Racks[].Nodes[].CloudProviderInstanceTypeID]'   # $TYPE_ID for each node
REQUEST_ID=$(curl -s -X POST -H "$AUTH" -H 'content-type: application/json' \
  "$API/account/$ACCOUNT_ID/cluster" --data @cluster.json | jq -r .data.requestId)
```

Start the loaders now ([loader-vm-aws](loader-vm-aws.md)). Then wait:

```sh
until curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/request/$REQUEST_ID" \
  | jq -e '.data.status | test("COMPLETED|FAILED")' > /dev/null; do sleep 30; done
CLUSTER_ID=$(curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/request/$REQUEST_ID" | jq -r .data.clusterId)
curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID" | jq -c '.data.cluster.dataCenters[0].scaling'
```

The last call must show `$TYPE_ID` in `instanceTypeIDs` and `$VCPU_MIN` in `vcpu.min`. A new X Cloud cluster has an `AUTOSCALING` request with status `QUEUED` in its request list. It is not a scaling event. Check the node count and `instanceId` again after each run.

## Read the nodes and the credentials

```sh
curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID/nodes" > nodes.json
jq -r '.data.nodes[] | [.privateIp, .azId, .instanceId] | @tsv' nodes.json
DC_ID=$(jq -r '.data.nodes[0].dcId' nodes.json)
DC=$(curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID" | jq -r '.data.cluster.dataCenters[0].name')
(umask 077; curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/connect?clusterId=$CLUSTER_ID" \
  | jq -r .data.credentials.password > scylladb_password)
```

A private cluster has no public node IPs. The rack name of each node is its AZ ID. Do not print the password.

## Peer the loader VPC

These calls do the steps of [VPC peering](https://cloud.docs.scylladb.com/stable/cluster-connections/vpc-peering/aws-vpc-peering.md) through the API. `allowCql: true` adds the loader CIDR to the cluster firewall. Without that rule, port 9042 is closed over the peering. The loader security group needs no CQL rule, because outbound traffic is open.

```sh
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
curl -s -X POST -H "$AUTH" -H 'content-type: application/json' \
  "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID/network/vpc/peer" --data \
  "{\"dcId\":$DC_ID,\"allowCql\":true,\"vpcId\":\"$VPC_ID\",\"cidrBlock\":\"$LOADER_CIDR\",\"ownerId\":\"$AWS_ACCOUNT\",\"regionId\":$REGION_ID}" > peer.json
PEER_ID=$(jq -r .data.id peer.json); PCX_ID=$(jq -r .data.externalId peer.json)   # pcx-...
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX_ID"
aws ec2 create-tags --resources "$PCX_ID" --tags "Key=scylladb-benchmark,Value=$RUN_ID"
aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-ids "$PCX_ID" \
  --filters Name=status-code,Values=active
aws ec2 create-route --route-table-id "$RTB_ID" --destination-cidr-block "$CLUSTER_CIDR" \
  --vpc-peering-connection-id "$PCX_ID"
curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID/network/firewall/allowed" | jq -c .data
```

The firewall list must contain `$LOADER_CIDR`. If it does not, add it with `POST .../network/firewall/allowed` and `{"ipAddress":"<loader-cidr>"}`.

## Options

- **Standard cluster.** Older accounts can create Standard clusters with a fixed node count ([Standard clusters](https://cloud.docs.scylladb.com/stable/cloud-setup/standard-clusters.md)). Remove `scaling`, and add `"instanceId":$TYPE_ID,"numberOfNodes":3`. Use `STANDARD_CLOUD` in the price call.
- **Public network path, only if the user asks.** Use `"broadcastType":"PUBLIC"` and no `cidrBlock`. Allow each loader IP with `POST .../network/firewall/allowed` and `{"ipAddress":"<loader-ip>/32"}`. Tell the user that this path is less secure and is not the path of a production application. Internet egress costs more than traffic in the region. Get both prices from `GET /deployment/cloud-provider/1/regions`. Mark every result "public network path".
- **Reuse a cluster** only if the user confirms that it has no production data. Check that `broadcastType` is `PRIVATE`. Read `dataCenters[0].cidrBlock` and the peerings (`GET .../network/vpc/peer`). Select a loader CIDR that overlaps none of them.

## Delete the peering and the cluster

Ask the user first. Deletion cannot be undone. `backupRetentionDays: 0` deletes the backups at once.

```sh
aws ec2 delete-route --route-table-id "$RTB_ID" --destination-cidr-block "$CLUSTER_CIDR"
curl -s -X DELETE -H "$AUTH" "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID/network/vpc/peer/$PEER_ID"
curl -s -X POST -H "$AUTH" -H 'content-type: application/json' "$API/account/$ACCOUNT_ID/cluster/$CLUSTER_ID/delete" \
  --data "{\"clusterName\":\"$RUN_ID\",\"backupRetentionDays\":0}"
curl -s -H "$AUTH" "$API/account/$ACCOUNT_ID/clusters" | jq -r '.data.clusters[] | [.id, .clusterName, .status] | @tsv'
```

The cluster is gone from the list when the deletion ends. The AWS side of the peering goes to `deleted`.
