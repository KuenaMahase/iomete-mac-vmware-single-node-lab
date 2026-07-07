# IOMETE 4.0.0-beta3 Single-Node Lab on Ubuntu ARM64 with VMware Fusion on macOS

This repository documents how I deployed IOMETE 4.0.0-beta3 on a single-node Ubuntu Server ARM64 VM running on VMware Fusion on an Apple Silicon MacBook Pro.

The goal was to validate IOMETE in a constrained lab environment and record the setup steps, issues, fixes, and final working state.

---

## Environment

### Host

- Apple MacBook Pro M4 Pro
- 24 GB RAM
- VMware Fusion
- macOS

### Guest VM

- Ubuntu Server ARM64
- Architecture: `aarch64`
- Hostname: `iomete-server`
- IP address: `192.168.1.29`
- Kubernetes: K3s `v1.36.2+k3s1`
- Helm: `v3.21.2`
- Single-node Kubernetes control-plane

---

## Main Components

- IOMETE Data Plane Enterprise `4.0.0-beta3`
- K3s Kubernetes
- Helm
- MinIO object storage
- PostgreSQL database
- Spark Operator
- Spark Connect
- Hive Metastore
- Prefect Server and Workers
- IOMETE Gateway
- IOMETE UI

---

## Namespace Layout

```text
iomete-system   # IOMETE platform services
data-plane-ns   # Managed data-plane namespace

```

---

## Deployment Flow

1. Created Ubuntu Server ARM64 VM in VMware Fusion.
2. Installed K3s.
3. Installed Helm.
4. Created `iomete-system` and `data-plane-ns`.
5. Deployed MinIO.
6. Created the `lakehouse` bucket.
7. Deployed PostgreSQL.
8. Applied IOMETE CRDs.
9. Configured service account and RBAC.
10. Generated Spark Operator webhook certificates.
11. Added the IOMETE Helm repository.
12. Rendered and inspected IOMETE chart `4.0.0-beta3`.
13. Verified ARM64 image support.
14. Installed IOMETE with Helm.
15. Fixed CPU and memory scheduling issues.
16. Fixed metastore ARM64 scheduling.
17. Fixed Spark Connect memory sizing.
18. Fixed gateway HTTP/HTTPS redirect.
19. Confirmed UI login and dashboard access.

---

## Final Working State

Final pod state:

```text
1 Completed
26 Running
```

Spark Connect:

```text
iom-spark-connect RUNNING
```

IOMETE UI:

```text
http://192.168.1.29:8080
```

Access command:

```bash
kubectl -n iomete-system port-forward svc/iom-gateway 8080:80 --address 0.0.0.0
```

---

## Important Fixes Applied

### Resource tuning

Default IOMETE resource requests were too high for the single-node VM. CPU and memory requests were reduced for lab use.

Most services were tuned to approximately:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
```

### Metastore ARM64 fix

Metastore initially tried to schedule on AMD64:

```text
kubernetes.io/arch=amd64
```

The VM was ARM64:

```text
kubernetes.io/arch=arm64
```

The metastore deployment was patched to use ARM64.

### Spark Connect memory fix

Spark Connect initially requested about 9 GiB memory for the driver. It was reduced for the lab:

```yaml
driver:
  memory: 1024m
  cores: 1
  coreRequest: 100m
  coreLimit: 500m
executor:
  memory: 512m
  cores: 1
  coreRequest: 100m
  coreLimit: 500m
  instances: 1
```

### Gateway redirect fix

After login, the UI redirected to:

```text
https://192.168.1.29/compute
```

This caused a 404 because the lab used:

```text
http://192.168.1.29:8080
```

The gateway ConfigMap was patched from HTTPS/443 to HTTP/8080.

---

## Evidence

The `evidence/` folder contains the final working cluster state:

- `pods.txt`
- `deployments.txt`
- `statefulsets.txt`
- `sparkapplications.txt`
- `services.txt`
- `node-describe.txt`
- `helm-status.txt`

---

## Recovery Script

The recovery script is stored here:

```text
scripts/reapply-mac-lab-patches.sh
```

Use it only if Helm overwrites the live lab fixes:

```bash
./scripts/reapply-mac-lab-patches.sh
```

---

## Notes

This is a lab deployment, not a production HA deployment.

For production, IOMETE should run on a properly sized multi-node Kubernetes cluster with external PostgreSQL, external object storage, ingress/TLS, monitoring, backup, and production-grade resource sizing.
