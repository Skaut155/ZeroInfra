# EMQX 5.8.8 on Kubernetes with Terraform

This Terraform configuration creates a two-node EMQX 5.8.8 cluster.

## Resources created

- Namespace `mqtt`
- StatefulSet `emqx` with exactly two replicas
- Mandatory pod anti-affinity on `kubernetes.io/hostname` (the pods cannot share a node)
- Headless Service `emqx-headless` for stable pod DNS and EMQX Kubernetes discovery
- Client-facing ClusterIP Service `emqx`
- ServiceAccount, namespaced Role and RoleBinding for reading Kubernetes Endpoints
- One PVC per StatefulSet pod, mounted at `/opt/emqx/data`
- A Kubernetes Secret containing a generated, shared Erlang distribution cookie

The image is pinned to `emqx:5.8.8`. The StatefulSet uses stable pod DNS names (`emqx-0` / `emqx-1`) for EMQX node identities.

## Prerequisites

- Terraform 1.5 or later
- A reachable Kubernetes API during `terraform plan` (the Kubernetes provider discovers resource schemas at plan time)
- A kubeconfig with permission to create namespaces, workloads, Services, PVCs, Secrets, ServiceAccounts and namespaced RBAC objects
- At least two schedulable Kubernetes nodes
- A default StorageClass, or set `storage_class_name`
- Network connectivity between the pods on TCP 4370 and 5369, plus access from each pod to `https://kubernetes.default.svc:443`

## Apply

```bash
terraform init
terraform plan
terraform apply
```

Optional configuration can be copied from `terraform.tfvars.example` into `terraform.tfvars`.

## Verify

```bash
kubectl get pods -n mqtt -o wide
kubectl get pvc -n mqtt
kubectl exec -n mqtt emqx-0 -- emqx ctl cluster status
```

The two pods should be on different nodes, both PVCs should be Bound, and the cluster status should report two running nodes.

## Important notes

- The headless Service sets `publishNotReadyAddresses: true` so a pod can discover its peer while the peer is still starting.
- Terraform state contains the generated cookie and Kubernetes Secret data. Protect the state backend and restrict access to it. For production, consider supplying the cookie from an external secret manager instead of generating it in Terraform.
- The MQTT Service is internal (`ClusterIP`). Change its type or add an Ingress/LoadBalancer according to your network design. Do not expose the Dashboard or TLS listener until you have configured appropriate authentication and certificates.
- This example persists EMQX data. Adjust PVC size and resource requests/limits for your workload.
- EMQX 5.8.x is an older release line. Keep it pinned only if that is an explicit compatibility requirement, and plan a tested upgrade path.
