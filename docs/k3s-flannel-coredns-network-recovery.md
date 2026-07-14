# K3s Flannel and CoreDNS Network Outage Recovery

## Incident summary

On 14 July 2026, the single-node IOMETE lab experienced a cluster-wide application outage. Most IOMETE workloads entered `CrashLoopBackOff`, `Error`, or remained `Running` but not ready.

The incident was caused by a broken or stale K3s pod-network state involving Flannel/CNI. CoreDNS was the most visible failing component, but it was not the original cause.

CoreDNS could not reach the Kubernetes API through the Kubernetes Service virtual IP:

```text
https://10.43.0.1:443
```

The decisive error was:

```text
dial tcp 10.43.0.1:443: connect: no route to host
```

CoreDNS also could not reach external DNS servers from its pod network:

```text
read udp 10.42.0.180:<port>->8.8.8.8:53: i/o timeout
```

Because DNS and Kubernetes Service networking were unavailable, IOMETE services could not resolve or connect to dependencies such as PostgreSQL, MinIO, Prefect, Typesense, the event stream, and other internal services. This produced a cascading failure across the platform.

---

## Environment

| Component | Value |
|---|---|
| Platform | VMware Fusion VM |
| Operating system | Ubuntu 26.04 LTS ARM64 |
| Kubernetes distribution | K3s |
| Kubernetes version | `v1.36.2+k3s1` |
| Node | `iomete-server` |
| Node IP | `192.168.1.29` |
| Pod CIDR | `10.42.0.0/16` |
| Service CIDR | `10.43.0.0/16` |
| Kubernetes API endpoint | `192.168.1.29:6443` |
| Kubernetes Service VIP | `10.43.0.1:443` |
| CoreDNS Service IP | `10.43.0.10` |

---

## User-visible symptoms

The cluster showed widespread failures:

```text
iom-app                         0/1   CrashLoopBackOff
iom-catalog                     0/1   Running
iom-cluster                     0/1   CrashLoopBackOff
iom-core                        0/1   CrashLoopBackOff
iom-event-stream                1/2   CrashLoopBackOff
iom-identity                    0/1   CrashLoopBackOff
iom-rest-catalog                0/1   CrashLoopBackOff
iom-socket                      0/1   CrashLoopBackOff
iom-sql                         0/1   Running
typesense                       0/1   CrashLoopBackOff
coredns                         0/1   CrashLoopBackOff
metrics-server                  0/1   CrashLoopBackOff
traefik                         0/1   CrashLoopBackOff
```

Some stateful and foundational services remained healthy:

- PostgreSQL
- MinIO
- Metastore
- Prefect Server
- Spark operators
- Spark Connect

This did not mean application networking was healthy. Those components were already running and did not all require the same failing dependency path during their readiness checks.

---

## Evidence and diagnosis

### 1. CoreDNS could not access the Kubernetes Service VIP

CoreDNS repeatedly reported:

```text
plugin/kubernetes: Failed to watch: failed to list *v1.EndpointSlice:
Get "https://10.43.0.1:443/apis/discovery.k8s.io/v1/endpointslices":
dial tcp 10.43.0.1:443: connect: no route to host
```

The same failure occurred for Services and Namespaces.

This prevented the CoreDNS Kubernetes plugin from synchronizing cluster DNS records.

### 2. CoreDNS readiness and liveness probes failed

The CoreDNS pod remained `Running` but not ready, and kubelet repeatedly restarted it:

```text
Readiness probe failed:
Get "http://10.42.0.180:8181/ready": context deadline exceeded
```

The `Running` phase alone therefore did not indicate a healthy DNS service.

### 3. The CoreDNS configuration was not the problem

The CoreDNS `Corefile` was structurally normal:

```text
kubernetes cluster.local in-addr.arpa ip6.arpa
forward . /etc/resolv.conf
```

Warnings about missing optional files were harmless:

```text
No files matching import glob pattern: /etc/coredns/custom/*.override
No files matching import glob pattern: /etc/coredns/custom/*.server
```

These warnings did not cause the outage.

### 4. The Kubernetes API and Service definition were healthy

The Kubernetes Service existed and pointed to the correct API endpoint:

```text
NAME         TYPE        CLUSTER-IP   PORT(S)
kubernetes   ClusterIP   10.43.0.1    443/TCP
```

Its endpoint was:

```text
192.168.1.29:6443
```

This proved that the Service object and API endpoint metadata were correct.

### 5. kube-proxy rules existed

The host contained the expected Kubernetes iptables rule:

```text
-A KUBE-SERVICES -d 10.43.0.1/32 -p tcp \
  --dport 443 -j KUBE-SVC-NPX46M4PTMTKRN6Y
```

Therefore, this was not simply a missing Kubernetes Service definition or an absent `KUBE-SERVICES` chain.

### 6. Host forwarding and firewall settings were not blocking traffic

The following values were already correct:

```text
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
```

Both UFW and firewalld were inactive.

### 7. The CNI bridge state was incomplete

Before recovery, `cni0` did not have its expected IPv4 address. The pod network could not correctly forward traffic between pod interfaces, the service rules, and the host.

After recovery, the expected state returned:

```text
cni0:
    inet 10.42.0.1/24

flannel.1:
    inet 10.42.0.0/32

route:
    10.42.0.0/24 dev cni0 src 10.42.0.1
```

The `10.42.0.0/32` address on `flannel.1` is valid for this single-node Flannel VXLAN setup. The important missing element before recovery was the functional `cni0` bridge address and route.

---

## Root cause

### Confirmed root cause

The confirmed root cause was a stale or broken K3s Flannel/CNI runtime state on the single node.

This disrupted:

1. Pod-to-Service communication.
2. Pod-to-Kubernetes-API communication through `10.43.0.1`.
3. Pod outbound communication and DNS forwarding.
4. CoreDNS synchronization with the Kubernetes API.
5. Service discovery for IOMETE workloads.

The exact event that originally placed Flannel/CNI into this state was not captured in the available logs. It would be inaccurate to claim that a particular NIC, Helm change, or gateway patch definitely caused it.

### What did not cause the outage

The following were ruled out as the primary cause:

- The IOMETE gateway HTTP/8080 redirect patch.
- The CoreDNS `Corefile`.
- Missing Kubernetes Service objects.
- An inactive API server.
- UFW or firewalld.
- Disabled IPv4 forwarding.
- Missing kube-proxy `KUBE-SERVICES` rules.

The gateway patch only changed generated browser redirect URLs from HTTPS/443 to HTTP/8080. It did not control Flannel, CNI, CoreDNS, or Kubernetes Service routing.

---

## Resolution

The recovery required two related actions.

### Step 1: Restart K3s

```bash
sudo modprobe br_netfilter
sudo modprobe vxlan

sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1

sudo systemctl restart k3s
sleep 30
```

This caused K3s to reinitialize its networking components, including Flannel and kube-proxy state.

### Step 2: Prove Kubernetes Service routing was restored

```bash
curl -sk --connect-timeout 5 \
  https://10.43.0.1:443/readyz
```

The response was:

```json
{
  "status": "Failure",
  "message": "Unauthorized",
  "reason": "Unauthorized",
  "code": 401
}
```

This `401 Unauthorized` response was a successful network test. It proved that the request reached the Kubernetes API through the Service VIP. Authentication failed only because the raw `curl` request did not supply Kubernetes credentials.

Before the repair, the same destination returned `no route to host`.

### Step 3: Recreate the CoreDNS pod

```bash
kubectl rollout restart deployment/coredns -n kube-system

kubectl rollout status deployment/coredns \
  -n kube-system \
  --timeout=180s
```

The new CoreDNS pod received a fresh pod network namespace and pod IP:

```text
coredns-74c744cc58-7vmhd   1/1   Running   10.42.0.207
```

The CNI bridge was then confirmed healthy:

```bash
ip -4 addr show dev cni0
ip -4 route | grep '10\.42'
ip -4 addr show dev flannel.1
```

Expected output:

```text
cni0      10.42.0.1/24
flannel.1 10.42.0.0/32
10.42.0.0/24 dev cni0 src 10.42.0.1
```

### Step 4: Allow dependent workloads to recover

Once CoreDNS was ready, the remaining components recovered gradually as their restart backoff periods expired.

No destructive action was required against PostgreSQL, MinIO, Metastore, or their persistent volumes.

After several minutes, the full platform returned to a healthy state:

```text
coredns                                      1/1   Running
metrics-server                               1/1   Running
traefik                                      1/1   Running
prefect-worker-data-plane-ns                 2/2   Running
iom-app                                      1/1   Running
iom-catalog                                  1/1   Running
iom-cluster                                  1/1   Running
iom-core                                     1/1   Running
iom-event-stream                             2/2   Running
iom-event-stream-proxy                       1/1   Running
iom-health-check                             1/1   Running
iom-identity                                 1/1   Running
iom-maintenance                              1/1   Running
iom-rest-catalog                             1/1   Running
iom-socket                                   1/1   Running
iom-sql                                      1/1   Running
typesense                                    1/1   Running
prefect-worker-iomete-system                 2/2   Running
prefect-worker-query-scheduling              2/2   Running
```

---

## Why restarting CoreDNS alone was not enough initially

CoreDNS was a victim of the broken pod network. Restarting only the CoreDNS container while Flannel/CNI was still unhealthy would recreate the same failure.

The correct order was:

1. Restore the K3s networking layer.
2. Verify access to `10.43.0.1:443`.
3. Recreate CoreDNS with a fresh pod network namespace.
4. Allow dependent applications to restart and become ready.

---

## Why the applications recovered slowly

Kubernetes applies exponential restart backoff to repeatedly failing containers. Even after the underlying network was repaired, some pods temporarily remained in:

- `CrashLoopBackOff`
- `Error`
- `Running` with `0/1` readiness

This was recovery lag rather than proof that the network repair failed.

The reliable health indicators were:

- CoreDNS became `1/1`.
- `cni0` regained `10.42.0.1/24`.
- The Kubernetes Service VIP returned an API response.
- Application readiness counts gradually changed to `1/1` or `2/2`.

---

## Safe recovery runbook

Use this sequence if the same symptoms occur again.

### 1. Capture the current state

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get svc -A

kubectl logs deployment/coredns \
  -n kube-system \
  --tail=200

kubectl describe pod \
  -n kube-system \
  $(kubectl get pod -n kube-system \
    -l k8s-app=kube-dns \
    -o jsonpath='{.items[0].metadata.name}')
```

### 2. Verify the Kubernetes API Service

```bash
kubectl get service kubernetes -n default -o wide
kubectl get endpoints kubernetes -n default -o wide

curl -sk --connect-timeout 5 \
  https://127.0.0.1:6443/readyz

curl -sk --connect-timeout 5 \
  https://10.43.0.1:443/readyz
```

Interpretation:

- `127.0.0.1:6443` succeeds but `10.43.0.1:443` fails: Service/CNI networking is broken.
- `10.43.0.1:443` returns `401 Unauthorized`: routing is working.
- Both fail: investigate the API server or K3s service itself.

### 3. Inspect CNI and Flannel

```bash
ip -4 addr show dev cni0
ip -4 addr show dev flannel.1
ip -4 route | grep -E '10\.42|10\.43|default'

sudo cat /run/flannel/subnet.env
```

Expected single-node pod bridge state:

```text
cni0      10.42.0.1/24
flannel.1 10.42.0.0/32
```

### 4. Verify kernel and firewall prerequisites

```bash
sudo modprobe br_netfilter
sudo modprobe vxlan

sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables

sudo ufw status verbose 2>/dev/null || true
sudo systemctl is-active firewalld 2>/dev/null || true
```

Expected values:

```text
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
```

### 5. Inspect Kubernetes networking rules

```bash
sudo iptables -t nat -S KUBE-SERVICES | head -n 50

sudo iptables-save | \
  grep -E '10\.43\.0\.1|KUBE-SERVICES|KUBE-SVC|CNI-|FLANNEL' | \
  head -n 200
```

Do not add a static route for `10.43.0.0/16`. Kubernetes ClusterIP addresses are virtual service addresses implemented by kube-proxy rules.

Do not flush iptables or the NAT table. Doing so can remove K3s, Flannel, Traefik, ServiceLB, and host-port rules.

### 6. Restart K3s networking

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1

sudo systemctl restart k3s
sleep 30

sudo systemctl status k3s --no-pager -l
```

### 7. Validate the Service VIP

```bash
curl -sk --connect-timeout 5 \
  https://10.43.0.1:443/readyz
```

A Kubernetes `401 Unauthorized` response confirms successful connectivity.

### 8. Recreate CoreDNS

```bash
kubectl rollout restart deployment/coredns -n kube-system

kubectl rollout status deployment/coredns \
  -n kube-system \
  --timeout=180s

kubectl get pods -n kube-system \
  -l k8s-app=kube-dns \
  -o wide
```

### 9. Watch platform recovery

```bash
watch -n 5 'kubectl get pods -A'
```

Allow several minutes for restart backoff to clear before manually restarting every application.

---

## Post-recovery validation

### Kubernetes and DNS

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system

kubectl logs deployment/coredns \
  -n kube-system \
  --tail=100
```

Confirm that the following errors no longer appear:

```text
no route to host
starting server with unsynced Kubernetes API
Failed to watch
```

### IOMETE workloads

```bash
kubectl get pods -n iomete-system
kubectl get pods -n data-plane-ns
```

All expected containers should show ready counts such as `1/1` or `2/2`.

### Services and endpoints

```bash
kubectl get svc -A
kubectl get endpointslice -A
```

### Metrics API

```bash
kubectl top nodes
kubectl top pods -A
```

### User interface

The lab UI should remain accessible at:

```text
http://192.168.1.29:8080
```

Verify that login redirects remain on HTTP port 8080 rather than HTTPS port 443.

---

## Preventive recommendations

### Preserve diagnostic evidence before restarting

When possible, save:

```bash
mkdir -p evidence/network-incident-$(date +%Y%m%d-%H%M%S)
```

Capture:

- `kubectl get pods -A -o wide`
- CoreDNS current and previous logs
- `kubectl describe` output
- K3s journal logs
- `ip addr` and `ip route`
- iptables and nftables rules
- `/run/flannel/subnet.env`

### Monitor CoreDNS readiness

CoreDNS is a strong early indicator of cluster networking failure. Alert when:

- CoreDNS is not ready.
- CoreDNS restarts increase unexpectedly.
- CoreDNS reports `Failed to watch`.
- CoreDNS cannot reach `10.43.0.1:443`.

### Monitor CNI bridge state

For this lab, periodically confirm:

```bash
ip -4 addr show dev cni0
```

The bridge should retain:

```text
10.42.0.1/24
```

### Avoid destructive network repair commands

Do not use the following as first-line recovery actions:

```bash
sudo iptables -F
sudo iptables -t nat -F
sudo nft flush ruleset
```

These commands can make the outage worse and remove unrelated working rules.

### Pin the K3s network interface only if recurrence proves it necessary

The VM has more than one network interface. A multi-NIC environment can sometimes cause incorrect interface selection, but the available incident evidence does not prove that it caused this outage.

If the issue recurs and logs show inconsistent interface selection, consider explicitly configuring:

```yaml
node-ip: 192.168.1.29
flannel-iface: ens192
```

Do not introduce this change solely on speculation. First inspect the active K3s configuration and journal logs.

---

## Final outcome

The incident was resolved without reinstalling K3s, redeploying IOMETE, modifying persistent storage, or changing the CoreDNS configuration.

The successful recovery sequence was:

1. Confirm the outage was cluster networking rather than an individual IOMETE service.
2. Verify the API endpoint, Service VIP, firewall, kernel settings, and kube-proxy rules.
3. Restart K3s to rebuild the stale Flannel/CNI runtime state.
4. Confirm `10.43.0.1:443` returned a Kubernetes API response.
5. Roll out a fresh CoreDNS pod.
6. Confirm `cni0` returned with `10.42.0.1/24`.
7. Allow Kubernetes restart backoff to expire.
8. Verify every IOMETE and Kubernetes workload became ready.

The platform returned to a fully healthy state.
