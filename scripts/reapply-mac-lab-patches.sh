#!/usr/bin/env bash
set -euo pipefail

NS=iomete-system

echo "1. Gateway HTTP/8080 patch"
kubectl get configmap iom-gateway-config -n "$NS" -o yaml > /tmp/iom-gateway-config.yaml
sed -i 's/set \$public_proto "https";/set $public_proto "http";/' /tmp/iom-gateway-config.yaml
sed -i 's/set \$public_port  443;/set $public_port  8080;/' /tmp/iom-gateway-config.yaml
kubectl apply -f /tmp/iom-gateway-config.yaml
kubectl rollout restart deployment/iom-gateway -n "$NS"

echo "2. Event stream single replica"
kubectl scale statefulset/iom-event-stream -n "$NS" --replicas=1 || true

echo "3. Metastore ARM64 selector and lab resources"
kubectl patch deployment metastore -n "$NS" --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/nodeSelector/kubernetes.io~1arch",
    "value": "arm64"
  }
]' || true

kubectl set resources deployment/metastore \
  -n "$NS" \
  --requests=cpu=100m,memory=256Mi \
  --limits=cpu=1,memory=1536Mi

echo "4. Lab resource requests for main deployments"
for d in \
  iom-catalog \
  iom-cluster \
  iom-core \
  iom-maintenance \
  iom-rest-catalog \
  iom-socket \
  iom-sql \
  prefect-server \
  spark-history \
  spark-operator-submit-service \
  typesense
do
  kubectl set resources deployment/$d \
    -n "$NS" \
    --requests=cpu=100m,memory=256Mi
done

echo "5. Prefect workers"
kubectl set resources deployment/prefect-worker-iomete-system \
  -n "$NS" \
  -c=prefect-worker-iomete-system \
  --requests=cpu=100m,memory=256Mi || true

kubectl set resources deployment/prefect-worker-query-scheduling \
  -n "$NS" \
  -c=prefect-worker-query-scheduling \
  --requests=cpu=100m,memory=256Mi \
  --limits=cpu=500m,memory=1Gi || true

kubectl set resources deployment/prefect-worker-query-scheduling \
  -n "$NS" \
  -c=post-install \
  --requests=cpu=10m,memory=32Mi \
  --limits=cpu=50m,memory=50Mi || true

echo "6. Spark Connect lab sizing"
kubectl patch sparkapplication iom-spark-connect \
  -n "$NS" \
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
  }' || true

echo "Done. Check pods:"
kubectl get pods -n "$NS"
