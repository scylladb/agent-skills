---
title: Loader VPC and VMs on AWS
tags: aws cli, vpc, subnet, availability zone id, internet gateway, security group, key pair, ec2, c7i, loaders, user data, pricing, cleanup, tags
---

# Loader VPC and VMs on AWS

The developer machine needs the AWS CLI, `curl`, `jq`, and `ssh`. Every resource gets the tag `scylladb-benchmark=$RUN_ID`. Create one loader in each cluster AZ ID. Each loader sets `rack=<its AZ ID>`, so each node gets the coordinator work of one loader.

Contents: [price and size](#price-and-size), [network](#create-the-loader-network), [VMs](#create-the-loaders), [prepare](#prepare-the-loaders), [clean up](#clean-up).

## Price and size

```sh
aws pricing get-products --region us-east-1 --service-code AmazonEC2 --filters \
  Type=TERM_MATCH,Field=instanceType,Value=c7i.8xlarge Type=TERM_MATCH,Field=regionCode,Value=$REGION \
  Type=TERM_MATCH,Field=operatingSystem,Value=Linux Type=TERM_MATCH,Field=tenancy,Value=Shared \
  Type=TERM_MATCH,Field=preInstalledSw,Value=NA Type=TERM_MATCH,Field=capacitystatus,Value=Used \
  --query 'PriceList[0]' --output text | jq -r '.terms.OnDemand[].priceDimensions[].pricePerUnit.USD'
```

This needs `pricing:GetProducts`. If the call fails, take the price from the [EC2 on-demand pricing page](https://aws.amazon.com/ec2/pricing/on-demand/) and write the source in the report.

Keep each loader at or below 50% CPU ([benchmarking tutorial](https://github.com/scylladb/scylladb/wiki/Benchmarking-Tutorial)). ScyllaDB's i8g benchmark used 4 × c7i.8xlarge ([i8g blog](https://www.scylladb.com/2026/01/22/scylladb-cloud-on-aws-i8g-and-i8ge/)).

## Create the loader network

The loader CIDR must not overlap the cluster `cidrBlock`. Use the same AZ IDs as `availabilityZoneIdsOverride` in [cluster-and-peering](cluster-and-peering.md#create-the-cluster). Run this while the cluster is created.

```sh
export AWS_REGION=$REGION
LOADER_CIDR=10.10.0.0/16
TAGS="{Key=scylladb-benchmark,Value=$RUN_ID}"
VPC_ID=$(aws ec2 create-vpc --cidr-block $LOADER_CIDR \
  --tag-specifications "ResourceType=vpc,Tags=[$TAGS,{Key=Name,Value=$RUN_ID}]" --query Vpc.VpcId --output text)
IGW_ID=$(aws ec2 create-internet-gateway --tag-specifications "ResourceType=internet-gateway,Tags=[$TAGS]" \
  --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
RTB_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --tag-specifications "ResourceType=route-table,Tags=[$TAGS]" \
  --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
MY_IP=$(curl -s https://checkip.amazonaws.com)
SG_ID=$(aws ec2 create-security-group --group-name $RUN_ID --vpc-id $VPC_ID --description "ScyllaDB benchmark loader" \
  --tag-specifications "ResourceType=security-group,Tags=[$TAGS]" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr "$MY_IP/32"
aws ec2 create-key-pair --key-name $RUN_ID --key-type ed25519 \
  --tag-specifications "ResourceType=key-pair,Tags=[$TAGS]" --query KeyMaterial --output text > $RUN_ID.pem
chmod 600 $RUN_ID.pem
```

Use AZ IDs (`use1-az2`), not AZ names. AWS maps AZ names to different AZ IDs in each account. The internet gateway is for SSH and the image download. CQL goes through the peering.

## Create the loaders

```sh
AMI_ID=$(aws ec2 describe-images --owners amazon --filters 'Name=name,Values=al2023-ami-2023.*-kernel-*-x86_64' \
  Name=state,Values=available --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
SCYLLA_IMAGE=scylladb/scylla:${SCYLLA_VERSION%.*}   # cqlsh of the cluster release
printf '#!/bin/bash\ndnf install -y docker\nsystemctl enable --now docker\nusermod -aG docker ec2-user
docker pull scylladb/cassandra-stress:4.0.0\ndocker pull %s\n' "$SCYLLA_IMAGE" > user-data.sh
: > loaders.txt; i=0
for AZ in $AZS; do
  SN=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.10.$((i+1)).0/24 --availability-zone-id $AZ \
    --tag-specifications "ResourceType=subnet,Tags=[$TAGS]" --query Subnet.SubnetId --output text)
  aws ec2 modify-subnet-attribute --subnet-id $SN --map-public-ip-on-launch
  aws ec2 associate-route-table --route-table-id $RTB_ID --subnet-id $SN > /dev/null
  ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type c7i.8xlarge --count 1 \
    --subnet-id $SN --key-name $RUN_ID --security-group-ids $SG_ID --user-data file://user-data.sh \
    --tag-specifications "ResourceType=instance,Tags=[$TAGS,{Key=Name,Value=$RUN_ID-$AZ}]" \
      "ResourceType=volume,Tags=[$TAGS]" "ResourceType=network-interface,Tags=[$TAGS]" \
    --query 'Instances[0].InstanceId' --output text)
  echo "$AZ $ID $i" >> loaders.txt; i=$((i+1))
done
aws ec2 wait instance-running --instance-ids $(awk '{print $2}' loaders.txt)
while read AZ ID I; do IP=$(aws ec2 describe-instances --instance-ids $ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text); echo "$AZ $IP $I $ID"; done < loaders.txt > l.txt
mv l.txt loaders.txt                      # columns: AZ ID, public IP, index, instance ID
```

## Prepare the loaders

[loader-helpers.sh](../scripts/loader-helpers.sh) defines `each` and `collect`. `each` runs one command on every loader at the same time. Source the file in each new shell. In a `while read` loop over `loaders.txt`, use `ssh -n`, or `ssh` reads the loop input. Do not use `-n` when you send a file on stdin.

```sh
. "$SKILL_DIR/scripts/loader-helpers.sh"
NODES=$(jq -r '[.data.nodes[].privateIp] | join(",")' nodes.json)
each 'cloud-init status --wait > /dev/null; docker images --format "{{.Repository}}:{{.Tag}}"'
while read AZ IP I ID; do
  scp -q -i $RUN_ID.pem scylladb_password ec2-user@$IP:.scylladb_password
  ssh -n -i $RUN_ID.pem ec2-user@$IP "chmod 600 ~/.scylladb_password; printf 'NODES=%s\nDC=%s\nRACK=%s\nLOADER=%s\nLOADERS=%s\nCS_IMAGE=scylladb/cassandra-stress:4.0.0\nSCYLLA_IMAGE=%s\n' \
    $NODES $DC $AZ $I $(wc -l < loaders.txt) $SCYLLA_IMAGE > ~/bench.env"
done < loaders.txt
each 'set -a; . ~/bench.env; for n in ${NODES//,/ }; do timeout 3 bash -c "</dev/tcp/$n/9042" && echo $n open || echo $n closed; done'
```

If a port is closed, check the route to the cluster CIDR and the firewall rule ([cluster-and-peering](cluster-and-peering.md#peer-the-loader-vpc)). cassandra-stress takes the password as a command-line option, so it shows in `ps` on the loader. Do not share the loaders.

## Clean up

Ask the user first. If the user says no, print these commands with the real IDs. Copy `~/results` from each loader before you delete the VMs. Delete the route and the peering first ([cluster-and-peering](cluster-and-peering.md#delete-the-peering-and-the-cluster)).

```sh
aws ec2 terminate-instances --instance-ids $(awk '{print $4}' loaders.txt)
aws ec2 wait instance-terminated --instance-ids $(awk '{print $4}' loaders.txt)
aws ec2 delete-security-group --group-id $SG_ID
aws ec2 delete-key-pair --key-name $RUN_ID
for SN in $(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --subnet-id $SN; done
aws ec2 delete-route-table --route-table-id $RTB_ID
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
aws ec2 delete-vpc --vpc-id $VPC_ID
rm -f $RUN_ID.pem scylladb_password
aws resourcegroupstaggingapi get-resources --tag-filters Key=scylladb-benchmark,Values=$RUN_ID \
  --query 'ResourceTagMappingList[].ResourceARN'
```

The tagging API can list a deleted resource for a short time. Check each type with a `describe-*` call.
