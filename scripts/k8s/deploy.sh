#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../.." && pwd)"
profile_name="${MINIKUBE_PROFILE:-cluster-chronicles}"

log() {
  printf '==> [cluster-deploy] %s\n' "$*"
}

cd "$project_root"
minikube status --profile "$profile_name" >/dev/null
minikube profile "$profile_name"

log "Building bootstrap application images on the OptiPlex"
docker build --network host --tag cluster-chronicles-backend:bootstrap app/backend
docker build \
  --network host \
  --file app/frontend/Dockerfile.k8s \
  --tag cluster-chronicles-frontend:bootstrap app/frontend

log "Building the Jenkins controller image"
docker build \
  --network host \
  --file ci/jenkins/Dockerfile.k8s \
  --tag cluster-chronicles-jenkins:bootstrap ci/jenkins

log "Loading bootstrap images into Minikube containerd"
for image_name in \
  cluster-chronicles-backend:bootstrap \
  cluster-chronicles-frontend:bootstrap \
  cluster-chronicles-jenkins:bootstrap; do
  minikube image load --profile "$profile_name" "$image_name"
done

log "Creating namespaces and generated secrets"
kubectl apply -k k8s/manifests/namespaces
bash "${script_dir}/create-secrets.sh"

log "Applying the complete Minikube overlay"
kubectl -n logging delete job kibana-saved-objects elasticsearch-bootstrap \
  --ignore-not-found=true --wait=true
kubectl apply -k k8s/overlays/minikube

log "Restarting workloads that use locally loaded bootstrap images"
kubectl -n cluster-chronicles rollout restart deployment/backend deployment/frontend
kubectl -n ci-cd rollout restart deployment/jenkins

log "Waiting for the application and platform services"
kubectl -n cluster-chronicles rollout status deployment/backend --timeout=5m
kubectl -n cluster-chronicles rollout status deployment/frontend --timeout=5m
kubectl -n ci-cd rollout status deployment/registry --timeout=5m
kubectl -n ci-cd rollout status deployment/jenkins --timeout=10m
kubectl -n observability rollout status deployment/prometheus --timeout=10m
kubectl -n observability rollout status deployment/alertmanager --timeout=5m
kubectl -n observability rollout status deployment/grafana --timeout=10m
kubectl -n observability rollout status deployment/kube-state-metrics --timeout=5m
kubectl -n observability rollout status daemonset/node-exporter --timeout=5m
kubectl -n logging rollout status statefulset/elasticsearch --timeout=10m
kubectl -n logging rollout status daemonset/fluent-bit --timeout=5m
kubectl -n logging rollout status deployment/elasticsearch-exporter --timeout=5m
kubectl -n logging rollout status deployment/kibana --timeout=12m
kubectl -n logging wait --for=condition=complete job/elasticsearch-bootstrap --timeout=8m
kubectl -n logging wait --for=condition=complete job/kibana-saved-objects --timeout=8m

log "Deployment summary"
kubectl get pods -A
kubectl get pv,pvc -A
kubectl get ingress -A
