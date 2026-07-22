---
title: Client Access and Networking
impact: HIGH
impactDescription: A ScyllaCluster that isn't exposed correctly is either unreachable from the application that needs it, or (worse) reachable only by accident in a way that breaks the moment pods reschedule or a second datacenter is added
tags: kubernetes, networking, exposeoptions, nodeservice, broadcast, loadbalancer, client-access
---

## `exposeOptions` Is How Clients and Nodes Find Each Other

A `ScyllaCluster` runs fine in-cluster with no `exposeOptions` at all, the default gives each node a `ClusterIP` Service reachable from inside the Kubernetes cluster. But the moment an application lives outside that cluster, or a second datacenter has to join, the defaults are wrong, and the failure mode is confusing: the cluster looks healthy, pods are `Running`, but clients either can't connect or connect to an address that stops working when a pod reschedules. `exposeOptions` is the field that controls this, and it has two independent halves, the Service the Operator creates per node, and the address each node *broadcasts*.

## `nodeService.type` — the Service Created Per Node

`exposeOptions.nodeService.type` sets what kind of Kubernetes Service the Operator creates for each ScyllaDB node:

- **`Headless`** — `clusterIP: None`; the DNS record resolves straight to the pod IP, no virtual IP is allocated. Lightest weight, in-cluster only.
- **`ClusterIP`** — a standard virtual IP routable only inside the Kubernetes cluster. **This is the default.**
- **`LoadBalancer`** — provisions an external load balancer per node on clouds that support it, giving each node an externally reachable address. This is what you need for clients (or a second DC) outside the Kubernetes cluster, and it costs one cloud load balancer *per node*, so it's a deliberate choice, not a default.

## `broadcastOptions` — the Address a Node Advertises

Creating a Service is only half of it, ScyllaDB nodes also *tell* clients and other nodes which address to use. `broadcastOptions` controls the source of that address, and it's set **independently for clients and for nodes** because the two kinds of traffic may live on different networks:

- `exposeOptions.broadcastOptions.clients.type` — the address advertised to clients (this drives ScyllaDB's `broadcast_rpc_address`).
- `exposeOptions.broadcastOptions.nodes.type` — the address advertised to other nodes for inter-node traffic.

Each takes one of:

- **`PodIP`** — broadcast the pod's IP. Works for clients and nodes that share the pod network (in-cluster, or a flat/routable pod network across clusters).
- **`ServiceClusterIP`** — broadcast the node Service's ClusterIP. In-cluster stable addressing that survives pod reschedules.
- **`ServiceLoadBalancerIngress`** — broadcast the external load balancer ingress address. Required when clients or peer nodes are outside the Kubernetes cluster.

### Matching the pieces

| Who needs to connect | `nodeService.type` | `broadcastOptions.clients.type` |
|---|---|---|
| Apps inside the same K8s cluster | `ClusterIP` (default) or `Headless` | `PodIP` or `ServiceClusterIP` |
| Apps outside the K8s cluster | `LoadBalancer` | `ServiceLoadBalancerIngress` |
| A second DC in a separate K8s cluster | `LoadBalancer` (or routable pod network) | see multi-DC in `scyllacluster-configuration.md` |

```yaml
spec:
  exposeOptions:
    nodeService:
      type: LoadBalancer          # external LB per node
    broadcastOptions:
      clients:
        type: ServiceLoadBalancerIngress
      nodes:
        type: ServiceLoadBalancerIngress
```

The rule of thumb: `nodeService.type` decides *whether an address exists*, `broadcastOptions.*.type` decides *which address gets handed out*. They have to be consistent, e.g. broadcasting `ServiceLoadBalancerIngress` while `nodeService.type` is `ClusterIP` gives clients an address that was never provisioned.

## Ports Worth Knowing

- **9042** — CQL (unencrypted)
- **9142** — CQL over TLS (see `security-tls-and-auth.md`)
- **8000 / 8043** — Alternator (DynamoDB API) plain / TLS (see the `scylladb-alternator` skill)
- **7000 / 7001** — inter-node (plain / TLS)

## Mapping to the Example Repo

The `tluck/Scylla-K8s-Example` repo drives these fields from `init.conf`: `nodeServiceType` → `exposeOptions.nodeService.type`, and `broadcastClientsType` / `broadcastNodesType` → the two `broadcastOptions` entries. It also ships `lb-svc.yaml` (a load-balancer Service) and `port_forward.bash` (a `kubectl port-forward` convenience for local access without a load balancer). Those are that repo's tooling choices around the same underlying Operator fields, not additional Operator features, when a user is on that repo, connect their `init.conf` values back to `exposeOptions`.
