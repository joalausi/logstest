# Cluster Chronicles

Cluster Chronicles migrates the completed Sherlock Logs VM platform to a single-node Minikube cluster. The target host is the OptiPlex (`optiplex`, `192.168.1.136`) because it has Docker, 4 CPU cores, 14 GiB RAM, and sufficient persistent disk for the application, Jenkins, Prometheus/Grafana, and EFK workloads.

## Architecture

The Minikube profile uses the Docker driver and containerd runtime. Workloads are separated into four namespaces:

| Namespace | Components | Pod Security level |
|---|---|---|
| `cluster-chronicles` | backend, two or more frontend replicas, HPA, PDB | Restricted |
| `ci-cd` | Jenkins, Kaniko/Trivy jobs, private Registry | Baseline |
| `observability` | Prometheus, Alertmanager, Grafana, exporters | Privileged for host metrics |
| `logging` | Elasticsearch, Fluent Bit, Kibana | Privileged for host log collection |

Ingress hosts are `cluster-chronicles.local`, `jenkins.cluster-chronicles.local`, `grafana.cluster-chronicles.local`, `prometheus.cluster-chronicles.local`, and `kibana.cluster-chronicles.local`.

Persistent volumes use Minikube host paths below `/data/cluster-chronicles` and the `Retain` reclaim policy. They survive pod replacement and workload redeployment, but deleting the entire Minikube profile also deletes the Minikube node and its data.

## Repository Layout

```text
k8s/
|-- config/          # containerd endpoint template for the HTTP Registry
|-- manifests/
|   |-- backend/       # one backend replica and ClusterIP Service
|   |-- frontend/      # two replicas, Service, PDB, and CPU HPA
|   |-- storage/       # static PVs and PVCs
|   |-- ci-cd/         # Jenkins and private Registry
|   |-- monitoring/    # Prometheus, Grafana, Alertmanager, dashboards
|   |-- logging/       # Elasticsearch, Fluent Bit, Kibana dashboards
|   |-- ingress/       # external host routing
|   |-- security/      # RBAC, NetworkPolicy, and Secret example
|   `-- namespaces/    # namespace and Pod Security labels
`-- overlays/minikube/ # deployable Kustomize overlay

scripts/k8s/
|-- bootstrap-optiplex.sh
|-- configure-registry.sh
|-- create-secrets.sh
|-- deploy.sh
|-- smoke-test.sh
|-- load-test-hpa.sh
|-- verify-observability.sh
`-- access.ps1
```

## Install and Deploy

Run these commands on the OptiPlex from the repository root:

```bash
bash scripts/k8s/bootstrap-optiplex.sh
bash scripts/k8s/deploy.sh
bash scripts/k8s/smoke-test.sh
bash scripts/k8s/verify-observability.sh
```

The bootstrap script installs Minikube and kubectl into `~/.local/bin`, verifies their checksums, creates the `cluster-chronicles` profile with the ingress and metrics-server addons, and configures containerd to pull from the cluster's HTTP Registry endpoint. No root installation is required because the OptiPlex user already belongs to the `docker` group.

`deploy.sh` builds three bootstrap images with the OptiPlex Docker daemon, loads them into Minikube containerd, generates Jenkins and Grafana passwords outside the repository, applies all manifests, imports dashboards, and waits for rollouts. Generated credentials are stored at `~/.config/cluster-chronicles/credentials.env` with mode `0600`.

## Access from Windows

Minikube's Docker network is private to the OptiPlex. Start an SSH tunnel from PowerShell:

```powershell
.\scripts\k8s\access.ps1
```

Add the names printed by the script to `C:\Windows\System32\drivers\etc\hosts` with address `127.0.0.1`, then use port `8080`, for example `http://cluster-chronicles.local:8080` and `http://grafana.cluster-chronicles.local:8080`.

For command-line checks directly on the OptiPlex, use the Minikube IP and a Host header:

```bash
curl -H 'Host: cluster-chronicles.local' "http://$(minikube -p cluster-chronicles ip)/api/health"
```

## CI/CD

Jenkins is provisioned from `ci/jenkins/casc-k8s.yaml` and executes `ci/Jenkinsfile.k8s` from the `cluster-chronicles` branch. A normal run:

1. renders the complete Kustomize overlay and verifies the Jenkins ServiceAccount permissions;
2. builds versioned backend and frontend images with isolated Kaniko jobs;
3. pushes them to the persistent in-cluster Registry;
4. scans both images with Trivy and fails on unfixed critical vulnerabilities;
5. updates the Kubernetes Deployments through a least-privilege ServiceAccount;
6. waits for both rollouts and runs an internal smoke test.

Set `ROLLBACK_TAG` to an existing Jenkins build number to redeploy existing images without rebuilding them.

Before running the job, push this branch to the Git remote configured in `ci/jenkins/casc-k8s.yaml`.

## Monitoring, Logging, and Alerts

Grafana provisions three dashboards automatically: Cluster Performance, Pod and Container Performance, and Application Performance. Prometheus discovers the API server, nodes, cAdvisor, annotated application pods, kube-state-metrics, node-exporter, Elasticsearch Exporter, and Fluent Bit.

Alert rules cover high node CPU and memory, low disk, frequent restarts, high container memory, long-pending pods, API server availability, Elasticsearch health, Fluent Bit output failures, and application HTTP error rate.

Fluent Bit tails `/var/log/containers`, enriches events with Kubernetes metadata, and writes `cluster-logs-*` indices. Kibana imports Cluster Logs, Application Logs, and Pod and Container Logs dashboards automatically.

## HPA Demonstration

Run on the OptiPlex:

```bash
./scripts/k8s/load-test-hpa.sh
```

The script creates temporary load generators in `ci-cd`, waits for the frontend HPA to scale above its minimum of two replicas, and removes the load deployment automatically on success, timeout, or interruption.

## Operations

```bash
kubectl get pods -A
kubectl get services -A
kubectl get ingress -A
kubectl get pv,pvc -A
kubectl -n cluster-chronicles get hpa frontend --watch
kubectl -n cluster-chronicles logs deployment/backend
kubectl -n logging logs daemonset/fluent-bit
kubectl describe pod -n <namespace> <pod-name>
```

Reapplying `bash scripts/k8s/deploy.sh` is safe. To stop without deleting data, run `minikube -p cluster-chronicles stop`. Deleting the profile is destructive and intentionally not automated.
