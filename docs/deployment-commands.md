# Full Deployment Commands

This document records the main commands used to deploy IOMETE 4.0.0-beta3 on a single-node Ubuntu Server ARM64 VM on VMware Fusion.

Sensitive values such as passwords are intentionally redacted.

---

## Table of Contents

1. [Verify VM Environment](#1-verify-vm-environment)
2. [Disable Swap](#2-disable-swap)
3. [Install K3s](#3-install-k3s)
4. [Install Helm](#4-install-helm)
5. [Create Namespaces](#5-create-namespaces)
6. [Deploy MinIO](#6-deploy-minio)
7. [Deploy PostgreSQL](#7-deploy-postgresql)
8. [Apply IOMETE CRDs](#8-apply-iomete-crds)
9. [Configure Service Account and RBAC](#9-configure-service-account-and-rbac)
10. [Generate Spark Operator Webhook Certificates](#10-generate-spark-operator-webhook-certificates)
11. [Add IOMETE Helm Repository](#11-add-iomete-helm-repository)
12. [Render and Inspect IOMETE Chart](#12-render-and-inspect-iomete-chart)
13. [Verify ARM64 Image Support](#13-verify-arm64-image-support)
14. [Create Initial IOMETE Values File](#14-create-initial-iomete-values-file)
15. [Install IOMETE](#15-install-iomete)
16. [Diagnose Pending Pods](#16-diagnose-pending-pods)
17. [Fix CPU and Memory Scheduling](#17-fix-cpu-and-memory-scheduling)
18. [Clean Rollout Deadlocks](#18-clean-rollout-deadlocks)
19. [Fix Metastore ARM64 Scheduling](#19-fix-metastore-arm64-scheduling)
20. [Fix Spark Connect Memory](#20-fix-spark-connect-memory)
21. [Fix Gateway Redirect HTTP/8080](#21-fix-gateway-redirect-http8080)
22. [Access IOMETE UI](#22-access-iomete-ui)
23. [Save Working State](#23-save-working-state)
24. [Final Health Checks](#24-final-health-checks)

---

## 1. Verify VM Environment

```bash
hostnamectl
uname -m
nproc
free -h
ip addr show
```

## 2. Disable Swap

```bash
sudo swapoff -a
sudo cp /etc/fstab /etc/fstab.bak
sudo sed -i '/ swap / s/^/#/' /etc/fstab
free -h
```

## 3. Install K3s

```bash
curl -sfL https://get.k3s.io | sh -

sudo systemctl status k3s
kubectl get nodes -o wide
```

Configure kubeconfig for the user:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config

kubectl get nodes
kubectl get pods -A
```

## 4. Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version
```

## 5. Create Namespaces

```bash
kubectl create namespace iomete-system
kubectl create namespace data-plane-ns

kubectl label namespace data-plane-ns iomete.com/managed=true
kubectl label namespace iomete-system iomete.com/managed=true

kubectl get ns --show-labels
```

## 6. Deploy MinIO

```bash
mkdir -p ~/iomete-install
cd ~/iomete-install

wget https://raw.githubusercontent.com/iomete/iomete-deployment/main/minio/minio-test-deployment.yaml

kubectl apply -n iomete-system -f minio-test-deployment.yaml

kubectl get pods -n iomete-system | grep minio
kubectl get pvc -n iomete-system
kubectl get svc -n iomete-system | grep minio
```

Port-forward MinIO:

```bash
kubectl -n iomete-system port-forward svc/minio 9000:9000 --address 0.0.0.0
```

Create the `lakehouse` bucket:

```bash
export AWS_ACCESS_KEY_ID=admin
export AWS_SECRET_ACCESS_KEY=password
export AWS_REGION=us-east-1
export AWS_ENDPOINT_URL=http://localhost:9000

aws s3 mb s3://lakehouse
aws s3 ls
```

## 7. Deploy PostgreSQL

```bash
cd ~/iomete-install

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

wget https://raw.githubusercontent.com/iomete/iomete-deployment/main/database/postgresql/postgresql-values.yaml

helm upgrade --install -n iomete-system \
  postgresql bitnami/postgresql \
  -f postgresql-values.yaml
```

Verify PostgreSQL:

```bash
kubectl get pods -n iomete-system | grep postgresql

export POSTGRES_PASSWORD=$(kubectl get secret --namespace iomete-system postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)

kubectl exec -n iomete-system postgresql-0 -- \
  env PGPASSWORD="$POSTGRES_PASSWORD" \
  psql --host postgresql -U postgres -d postgres -p 5432 -c "\conninfo"
```

## 8. Apply IOMETE CRDs

```bash
cd ~/iomete-install

wget https://raw.githubusercontent.com/iomete/iomete-deployment/main/iomete-crds.yaml

kubectl apply --server-side -f iomete-crds.yaml

kubectl get crd | grep spark
```

## 9. Configure Service Account and RBAC

```bash
cd ~/iomete-install

wget https://raw.githubusercontent.com/iomete/iomete-deployment/main/service-account.yaml
wget https://raw.githubusercontent.com/iomete/iomete-deployment/main/role-binding-to-control-plane.yaml

kubectl apply -n data-plane-ns -f service-account.yaml

export CP_NAMESPACE=iomete-system
cp role-binding-to-control-plane.yaml role-binding-to-control-plane-data-plane-ns.yaml
sed -i "s/{{control-plane-namespace}}/$CP_NAMESPACE/g" role-binding-to-control-plane-data-plane-ns.yaml

kubectl apply -n data-plane-ns -f role-binding-to-control-plane-data-plane-ns.yaml

kubectl apply -n iomete-system -f service-account.yaml
```

Verify RBAC:

```bash
kubectl auth can-i create pods \
  --as=system:serviceaccount:data-plane-ns:lakehouse-service-account \
  -n data-plane-ns

kubectl auth can-i create sparkapplications.sparkoperator.k8s.io \
  --as=system:serviceaccount:data-plane-ns:lakehouse-service-account \
  -n data-plane-ns

kubectl auth can-i get pods/log \
  --as=system:serviceaccount:data-plane-ns:lakehouse-service-account \
  -n data-plane-ns
```

## 10. Generate Spark Operator Webhook Certificates

```bash
cd ~/iomete-install

wget -O gencerts.sh https://raw.githubusercontent.com/iomete/iomete-deployment/main/gencerts.sh
chmod +x gencerts.sh

./gencerts.sh -n iomete-system -s spark-operator-webhook -r spark-operator-webhook-certs
```

Apply webhook manifest if required:

```bash
kubectl apply -n iomete-system -f spark-operator-webhook.yaml
```

Verify:

```bash
kubectl get secret spark-operator-webhook-certs -n iomete-system
kubectl get mutatingwebhookconfiguration | grep spark
```

## 11. Add IOMETE Helm Repository

```bash
helm repo add iomete https://chartmuseum.iomete.com
helm repo update

helm search repo iomete/iomete-data-plane-enterprise --devel --version 4.0.0-beta3
```

## 12. Render and Inspect IOMETE Chart

```bash
export V=4.0.0-beta3

helm template data-plane iomete/iomete-data-plane-enterprise \
  --version "$V" \
  -n iomete-system \
  > /tmp/iomete-${V}-rendered.yaml
```

Extract chart images:

```bash
awk '/image:/{print $2}' /tmp/iomete-${V}-rendered.yaml \
  | tr -d '"' \
  | sort -u > ~/iomete-${V}-chart-images.txt

cat ~/iomete-${V}-chart-images.txt
```

## 13. Verify ARM64 Image Support

Install tools:

```bash
sudo apt update
sudo apt install -y skopeo jq
```

Check all images:

```bash
export V=4.0.0-beta3

rm -f ~/iomete-${V}-image-platforms.txt
rm -f ~/iomete-${V}-missing-arm64.txt
rm -f ~/iomete-${V}-inspect-failed.txt

while read image; do
  echo "===== $image =====" | tee -a ~/iomete-${V}-image-platforms.txt

  raw=$(skopeo inspect --raw docker://$image 2>/tmp/skopeo-error.txt)

  if [ $? -ne 0 ]; then
    echo "FAILED TO INSPECT: $image" | tee -a ~/iomete-${V}-image-platforms.txt
    cat /tmp/skopeo-error.txt | tee -a ~/iomete-${V}-image-platforms.txt
    echo "$image" >> ~/iomete-${V}-inspect-failed.txt
    continue
  fi

  platforms=$(echo "$raw" | jq -r '
    if .manifests then
      [.manifests[].platform
        | select(.os == "linux")
        | "\(.os)/\(.architecture)"
      ] | unique | join(", ")
    else
      "\(.os)/\(.architecture)"
    end
  ')

  echo "$platforms" | tee -a ~/iomete-${V}-image-platforms.txt
  echo "$platforms" | grep -q "linux/arm64" || echo "$image" >> ~/iomete-${V}-missing-arm64.txt
done < ~/iomete-${V}-chart-images.txt
```

Verify no missing ARM64 images:

```bash
cat ~/iomete-${V}-missing-arm64.txt 2>/dev/null || true
cat ~/iomete-${V}-inspect-failed.txt 2>/dev/null || true
```

## 14. Create Initial IOMETE Values File

Create a lab values file.

> **Important:** do not commit real passwords to GitHub.

```bash
cat > ~/iomete-4.0.0-beta3-mac-lab-values.yaml <<'EOF_VALUES'
name: iomete-mac-lab

adminUser:
  username: "admin"
  email: "admin@example.com"
  firstName: Admin
  lastName: Admin
  temporaryPassword: "admin"

authentication:
  redirectUrlWhitelist:
    - "*"

database:
  type: postgresql
  host: "postgresql"
  port: "5432"
  user: "iomete_user"
  password: "iomete_pass"
  prefix: "iomete_"
  adminCredentials:
    user: "postgres"
    password: "<REDACTED_POSTGRES_ADMIN_PASSWORD>"
  ssl:
    enabled: false
    mode: "disable"

storage:
  bucketName: "lakehouse"
  type: "minio"
  minioSettings:
    endpoint: "http://minio:9000"
    accessKey: "admin"
    secretKey: "password"

docker:
  imagePullSecrets: []

namespaces:
  - data-plane-ns
EOF_VALUES
```

## 15. Install IOMETE

```bash
export V=4.0.0-beta3

helm upgrade --install data-plane iomete/iomete-data-plane-enterprise \
  --version "$V" \
  -n iomete-system \
  -f ~/iomete-4.0.0-beta3-mac-lab-values.yaml \
  --timeout 30m \
  --wait
```

Check status:

```bash
helm status data-plane -n iomete-system
kubectl get pods -n iomete-system
```

## 16. Diagnose Pending Pods

```bash
kubectl get pods -n iomete-system -o wide

for p in $(kubectl get pods -n iomete-system --field-selector=status.phase=Pending -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  echo
  echo "=============================="
  echo "$p"
  echo "=============================="
  kubectl describe pod "$p" -n iomete-system | sed -n '/Events:/,$p'
done
```

Check node reservations:

```bash
kubectl describe node iomete-server | sed -n '/Allocated resources:/,$p' | head -80
```

## 17. Fix CPU and Memory Scheduling

Lower lab resource requests.

```bash
for d in \
  iom-catalog \
  iom-cluster \
  iom-core \
  iom-maintenance \
  iom-rest-catalog \
  iom-socket \
  iom-sql \
  metastore \
  prefect-server \
  spark-history \
  spark-operator-submit-service \
  typesense
do
  echo "Patching $d"
  kubectl set resources deployment/$d \
    -n iomete-system \
    --requests=cpu=100m,memory=256Mi
done
```

Patch Prefect workers separately:

```bash
kubectl set resources deployment/prefect-worker-iomete-system \
  -n iomete-system \
  -c=prefect-worker-iomete-system \
  --requests=cpu=100m,memory=256Mi

kubectl set resources deployment/prefect-worker-query-scheduling \
  -n iomete-system \
  -c=prefect-worker-query-scheduling \
  --requests=cpu=100m,memory=256Mi \
  --limits=cpu=500m,memory=1Gi

kubectl set resources deployment/prefect-worker-query-scheduling \
  -n iomete-system \
  -c=post-install \
  --requests=cpu=10m,memory=32Mi \
  --limits=cpu=50m,memory=50Mi
```

## 18. Clean Rollout Deadlocks

On a small single-node lab, rolling updates may create new pods before removing old pods. Scale down and back up to remove duplicates.

```bash
for d in \
  iom-catalog \
  iom-cluster \
  iom-core \
  iom-maintenance \
  iom-rest-catalog \
  iom-socket \
  iom-sql \
  metastore \
  prefect-server \
  prefect-worker-iomete-system \
  prefect-worker-query-scheduling \
  spark-history \
  spark-operator-submit-service \
  typesense
do
  echo "Scaling down $d"
  kubectl scale deployment/$d -n iomete-system --replicas=0
done
```

Wait:

```bash
watch -n 2 "kubectl get pods -n iomete-system | egrep 'iom-catalog|iom-cluster|iom-core|iom-maintenance|iom-rest-catalog|iom-socket|iom-sql|metastore|prefect-server|prefect-worker|spark-history|spark-operator-submit-service|typesense' || true"
```

Scale up:

```bash
for d in \
  iom-catalog \
  iom-cluster \
  iom-core \
  iom-maintenance \
  iom-rest-catalog \
  iom-socket \
  iom-sql \
  metastore \
  prefect-server \
  prefect-worker-iomete-system \
  prefect-worker-query-scheduling \
  spark-history \
  spark-operator-submit-service \
  typesense
do
  echo "Scaling up $d"
  kubectl scale deployment/$d -n iomete-system --replicas=1
done
```

## 19. Fix Metastore ARM64 Scheduling

Check metastore selector:

```bash
kubectl get deployment metastore -n iomete-system \
  -o jsonpath='{.spec.template.spec.nodeSelector}{"\n"}'
```

Patch to ARM64:

```bash
kubectl patch deployment metastore \
  -n iomete-system \
  --type='json' \
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/nodeSelector/kubernetes.io~1arch",
      "value": "arm64"
    }
  ]'
```

Set smaller resources:

```bash
kubectl set resources deployment/metastore \
  -n iomete-system \
  --requests=cpu=100m,memory=256Mi \
  --limits=cpu=1,memory=1536Mi
```

Restart:

```bash
kubectl rollout restart deployment/metastore -n iomete-system
kubectl rollout status deployment/metastore -n iomete-system --timeout=5m
```

## 20. Fix Spark Connect Memory

Inspect pending driver:

```bash
kubectl get pod iom-spark-connect-driver -n iomete-system \
  -o jsonpath='{range .spec.containers[*]}{.name}{" requests="}{.resources.requests}{" limits="}{.resources.limits}{"\n"}{end}'

kubectl get pod iom-spark-connect-driver -n iomete-system \
  -o jsonpath='{.metadata.ownerReferences}{"\n"}'

kubectl get sparkapplications -n iomete-system
```

Patch SparkApplication:

```bash
kubectl patch sparkapplication iom-spark-connect \
  -n iomete-system \
  --type='merge' \
  -p='{
    "spec": {
      "driver": {
        "memory": "1024m",
        "cores": 1,
        "coreRequest": "100m",
        "coreLimit": "500m"
      },
      "executor": {
        "memory": "512m",
        "cores": 1,
        "coreRequest": "100m",
        "coreLimit": "500m",
        "instances": 1
      }
    }
  }'
```

Delete the old driver pod:

```bash
kubectl delete pod iom-spark-connect-driver -n iomete-system
```

Verify:

```bash
kubectl get sparkapplications -n iomete-system

kubectl get pod iom-spark-connect-driver -n iomete-system \
  -o jsonpath='{range .spec.containers[*]}{.name}{" requests="}{.resources.requests}{" limits="}{.resources.limits}{"\n"}{end}'
```

## 21. Fix Gateway Redirect HTTP/8080

Check rendered gateway configuration:

```bash
helm get manifest data-plane -n iomete-system > ~/data-plane-rendered-live.yaml

grep -niE 'public_proto|public_port|https|ingress' \
  ~/data-plane-rendered-live.yaml -C 5
```

Patch ConfigMap:

```bash
kubectl get configmap iom-gateway-config \
  -n iomete-system \
  -o yaml > /tmp/iom-gateway-config.yaml

cp /tmp/iom-gateway-config.yaml /tmp/iom-gateway-config.yaml.bak

sed -i 's/set \$public_proto "https";/set $public_proto "http";/' /tmp/iom-gateway-config.yaml
sed -i 's/set \$public_port  443;/set $public_port  8080;/' /tmp/iom-gateway-config.yaml

kubectl apply -f /tmp/iom-gateway-config.yaml
```

Confirm:

```bash
kubectl get configmap iom-gateway-config \
  -n iomete-system \
  -o yaml | grep -n 'public_proto\|public_port' -C 2
```

Restart gateway:

```bash
kubectl rollout restart deployment/iom-gateway -n iomete-system
kubectl rollout status deployment/iom-gateway -n iomete-system --timeout=3m
```

## 22. Access IOMETE UI

Start port-forward:

```bash
kubectl -n iomete-system port-forward svc/iom-gateway 8080:80 --address 0.0.0.0
```

Open:

```text
http://192.168.1.29:8080
```

Login:

```text
admin / admin
```

## 23. Save Working State

```bash
mkdir -p ~/iomete-working-state

kubectl get pods -n iomete-system -o wide > ~/iomete-working-state/pods.txt
kubectl get deploy -n iomete-system -o wide > ~/iomete-working-state/deployments.txt
kubectl get statefulset -n iomete-system -o wide > ~/iomete-working-state/statefulsets.txt
kubectl get sparkapplications -n iomete-system -o wide > ~/iomete-working-state/sparkapplications.txt
kubectl get svc -n iomete-system -o wide > ~/iomete-working-state/services.txt
kubectl describe node iomete-server > ~/iomete-working-state/node-describe.txt
kubectl get configmap iom-gateway-config -n iomete-system -o yaml > ~/iomete-working-state/iom-gateway-config.yaml
helm get values data-plane -n iomete-system -a > ~/iomete-working-state/helm-values-current.yaml
helm status data-plane -n iomete-system > ~/iomete-working-state/helm-status.txt
```

## 24. Final Health Checks

```bash
kubectl get pods -n iomete-system

kubectl get pods -n iomete-system --no-headers | awk '{print $3}' | sort | uniq -c

kubectl get sparkapplications -n iomete-system

kubectl describe node iomete-server | sed -n '/Allocated resources:/,$p' | head -80
```
