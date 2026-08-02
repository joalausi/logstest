#!/usr/bin/env bash
set -euo pipefail

profile_name="${MINIKUBE_PROFILE:-cluster-chronicles}"
minikube profile "$profile_name" >/dev/null
cluster_ip="$(minikube ip --profile "$profile_name")"
smoke_pod="cluster-chronicles-smoke-$RANDOM"

cleanup() {
  kubectl -n ci-cd delete pod "$smoke_pod" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

check_ingress() {
  local host_name="$1"
  local path_name="$2"
  printf 'Checking http://%s%s\n' "$host_name" "$path_name"
  curl --fail --silent --show-error \
    --connect-timeout 5 \
    --max-time 15 \
    --header "Host: ${host_name}" \
    "http://${cluster_ip}${path_name}" >/dev/null
}

kubectl -n cluster-chronicles wait --for=condition=Available deployment/backend deployment/frontend --timeout=3m
kubectl -n ci-cd wait --for=condition=Available deployment/jenkins deployment/registry --timeout=3m
kubectl -n observability wait --for=condition=Available deployment/prometheus deployment/grafana --timeout=3m
kubectl -n logging wait --for=condition=Available deployment/kibana --timeout=3m

unbound_claims="$(kubectl get pvc -A --no-headers | awk '$3 != "Bound" {print}')"
if [[ -n "$unbound_claims" ]]; then
  printf 'Unbound PVCs:\n%s\n' "$unbound_claims" >&2
  exit 1
fi

check_ingress cluster-chronicles.local /api/health
check_ingress prometheus.cluster-chronicles.local /-/ready
check_ingress grafana.cluster-chronicles.local /api/health
check_ingress kibana.cluster-chronicles.local /api/status
check_ingress jenkins.cluster-chronicles.local /login

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${smoke_pod}
  namespace: ci-cd
  labels:
    app.kubernetes.io/name: smoke-test
    app.kubernetes.io/part-of: cluster-chronicles
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 100
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: smoke
      image: curlimages/curl:8.15.0
      command: ["sh", "-ec"]
      args:
        - |
          curl -fsS --connect-timeout 5 --max-time 15 http://frontend.cluster-chronicles.svc.cluster.local/api/health
          curl -fsS --connect-timeout 5 --max-time 15 http://elasticsearch.logging.svc.cluster.local:9200/_cluster/health
          curl -fsS --connect-timeout 5 --max-time 15 http://prometheus.observability.svc.cluster.local:9090/api/v1/rules >/dev/null
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
EOF
kubectl -n ci-cd wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${smoke_pod}" --timeout=3m
kubectl -n ci-cd logs "$smoke_pod"

kubectl -n cluster-chronicles get deployments,pods,services,hpa,ingress
kubectl get pv
printf 'Cluster Chronicles smoke test passed.\n'
