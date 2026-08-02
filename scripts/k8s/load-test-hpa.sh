#!/usr/bin/env bash
set -euo pipefail

load_replicas="${LOAD_REPLICAS:-12}"
scale_timeout="${HPA_SCALE_TIMEOUT:-300}"
cleanup() {
  kubectl -n ci-cd delete deployment frontend-load --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-load
  namespace: ci-cd
  labels:
    app.kubernetes.io/name: frontend-load
    app.kubernetes.io/part-of: cluster-chronicles
spec:
  replicas: ${load_replicas}
  selector:
    matchLabels:
      app.kubernetes.io/name: frontend-load
  template:
    metadata:
      labels:
        app.kubernetes.io/name: frontend-load
        app.kubernetes.io/part-of: cluster-chronicles
    spec:
      restartPolicy: Always
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: load
          image: busybox:1.37
          command: ["sh", "-ec"]
          args:
            - |
              for worker in 1 2 3 4 5 6 7 8; do
                (
                  while true; do
                    wget -q -O /dev/null http://frontend.cluster-chronicles.svc.cluster.local/
                  done
                ) &
              done
              wait
          resources:
            requests:
              cpu: 10m
              memory: 8Mi
            limits:
              cpu: 100m
              memory: 32Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
EOF
kubectl -n ci-cd rollout status deployment/frontend-load --timeout=3m

printf 'Generating load and waiting for the frontend to scale above two replicas.\n'
deadline=$((SECONDS + scale_timeout))
while (( SECONDS < deadline )); do
  current_replicas="$(kubectl -n cluster-chronicles get hpa frontend -o jsonpath='{.status.currentReplicas}')"
  desired_replicas="$(kubectl -n cluster-chronicles get hpa frontend -o jsonpath='{.status.desiredReplicas}')"
  current_cpu="$(kubectl -n cluster-chronicles get hpa frontend -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null || true)"
  printf '  current=%s desired=%s cpu=%s%%\n' \
    "${current_replicas:-unknown}" "${desired_replicas:-unknown}" "${current_cpu:-unknown}"

  if [[ "${current_replicas:-0}" -gt 2 || "${desired_replicas:-0}" -gt 2 ]]; then
    kubectl -n cluster-chronicles get hpa frontend
    kubectl -n cluster-chronicles get pods -l app.kubernetes.io/name=frontend
    printf 'HPA scale-up verified. Temporary load will now be removed.\n'
    exit 0
  fi
  sleep 10
done

echo "Frontend HPA did not scale within ${scale_timeout} seconds." >&2
kubectl -n cluster-chronicles describe hpa frontend >&2
exit 1
