---
title: Security — TLS, mTLS, and Authentication
impact: HIGH
impactDescription: A cluster left on the default superuser with no encryption is a data-exposure incident waiting to happen, and the Operator's auto-generated TLS makes securing it far easier than teams assume, so there's little excuse to skip it
tags: kubernetes, tls, mtls, authentication, certificates, security, cqlsh
---

## Authentication: Change the Default Superuser Immediately

ScyllaDB ships with a default superuser, `cassandra` / `cassandra`. On a fresh cluster this account exists and is a real credential, treating it as a placeholder that "doesn't count" is how clusters end up in production still using it. Enable authentication and replace it as a first-class deployment step, not a follow-up.

Password authentication itself is configured through `scylla.yaml` via `scyllaConfig` (see `scyllacluster-configuration.md`):

```yaml
authenticator: PasswordAuthenticator
authorizer: CassandraAuthorizer
```

On ScyllaDB 2026.2+ the superuser can be provisioned with a pre-hashed (salted) password rather than a plaintext one, so credentials don't have to sit in cleartext in a manifest. When a deployment enables TLS it should also enable auth, encrypting the transport while leaving the default credentials in place secures the wire but not the door.

## Encryption In Transit: The Operator Generates the Certs For You

The point most teams miss is that you usually don't need cert-manager or your own PKI for cluster traffic. With the `AutomaticTLSCertificates` feature, the Operator **generates and rotates** serving and client certificates per `ScyllaCluster` and configures the nodes to use them. Two channels are covered:

- **Client-to-node** — applications connect over the TLS CQL port **9142** instead of plaintext 9042.
- **Node-to-node** — inter-node traffic between ScyllaDB pods is encrypted.

(This is distinct from the cert-manager dependency in `installation-and-upgrades.md`, that one is only for the *Operator's admission webhook*, not for cluster or client traffic.)

### The resources the Operator creates per cluster

| Resource | Kind | Contents |
|---|---|---|
| `<cluster>-local-serving-ca` | ConfigMap | the CA bundle (`ca-bundle.crt`) clients trust |
| `<cluster>-local-user-admin` | Secret | admin client cert + key (`tls.crt` / `tls.key`) for mTLS |
| `<cluster>-local-cql-connection-configs-admin` | Secret | a pre-built connection bundle for drivers |
| `<cluster>-alternator-local-serving-ca` | ConfigMap | CA for Alternator (DynamoDB API) TLS |

### Extracting what a client needs

```bash
# CA the client should trust
kubectl -n scylla get configmap <cluster>-local-serving-ca \
  --template='{{ index .data "ca-bundle.crt" }}' > ca.crt

# Admin client cert + key (for mTLS)
kubectl -n scylla get secret <cluster>-local-user-admin \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > client.crt
kubectl -n scylla get secret <cluster>-local-user-admin \
  -o jsonpath='{.data.tls\.key}' | base64 -d > client.key
```

Point `cqlsh`/driver at port **9142** with the CA (and the client cert/key when using mTLS).

## mTLS Can Replace Passwords

With mutual TLS, the client presents a certificate and ScyllaDB maps that certificate's identity to a role, so the certificate *is* the authentication, no password needed. This is why an mTLS deployment can drop password auth entirely rather than layering both. The admin cert above corresponds to the admin role; issuing per-application client certs is how you give distinct identities without distributing shared passwords.

## Custom Certificates: When the Operator's Aren't Enough

Operator-generated certs are the right default for a single cluster. You supply your own when something outside the Operator's control has to trust the chain, the common case is a **multi-datacenter** deployment spanning separate Kubernetes clusters, where both DCs must share a CA (see multi-DC in `scyllacluster-configuration.md`). Custom serving certs are mounted via a Secret and CA ConfigMap referenced by the cluster, replacing the auto-generated pair.

## Mapping to the Example Repo

The `tluck/Scylla-K8s-Example` repo exposes this surface through `init.conf` flags: `enableAuth` (password auth + superuser creds), `enableTLS` (which it requires `enableAuth` alongside), `mTLS` (certificate auth instead of passwords), and `customCerts` (bring-your-own certs for the dual-DC case). The helper scripts `extract_ca.bash`, `get_tls_keys.bash`, and `client_tls.bash`, plus the repo's `TLS Certs - Use Cases.md`, automate the extraction steps above. Those are that repo's conventions wrapping the same Operator-managed Secrets/ConfigMaps, not separate mechanisms.
