#!/usr/bin/env bash
set -euo pipefail

profile_name="${MINIKUBE_PROFILE:-cluster-chronicles}"
minikube profile "$profile_name" >/dev/null
cluster_ip="$(minikube ip --profile "$profile_name")"

fetch_ingress() {
  local host_name="$1"
  local path_name="$2"
  curl -fsS --connect-timeout 5 --max-time 30 \
    --header "Host: ${host_name}" \
    "http://${cluster_ip}${path_name}"
}

printf '%s\n' 'Prometheus targets:'
targets_json="$(fetch_ingress prometheus.cluster-chronicles.local /api/v1/targets)"
python3 -c '
import json, sys
payload = json.load(sys.stdin)
targets = payload["data"]["activeTargets"]
for target in sorted(targets, key=lambda item: (item["labels"].get("job", ""), item["scrapeUrl"])):
    print("  {}: {}".format(target["labels"].get("job", "unknown"), target["health"]))
unhealthy = [target for target in targets if target["health"] != "up"]
if unhealthy:
    print("Unhealthy Prometheus targets detected", file=sys.stderr)
    sys.exit(1)
' <<<"$targets_json"

printf '%s\n' 'Prometheus alert rules:'
rules_json="$(fetch_ingress prometheus.cluster-chronicles.local /api/v1/rules)"
python3 -c '
import json, sys
expected = {
    "NodeHighCPU", "NodeLowDiskSpace", "NodeHighMemory",
    "PodRestartingFrequently", "ContainerHighMemory", "PodPendingTooLong",
    "KubernetesAPIServerDown", "ElasticsearchClusterNotGreen",
    "FluentBitLogCollectionErrors", "ApplicationHighErrorRate",
}
payload = json.load(sys.stdin)
loaded = {
    rule["name"]
    for group in payload["data"]["groups"]
    for rule in group["rules"]
    if rule.get("type") == "alerting"
}
missing = expected - loaded
print("  " + ", ".join(sorted(expected & loaded)))
if missing:
    print("Missing alert rules: " + ", ".join(sorted(missing)), file=sys.stderr)
    sys.exit(1)
' <<<"$rules_json"

grafana_password="$(kubectl -n observability get secret grafana-admin -o jsonpath='{.data.password}' | base64 --decode)"
grafana_json="$(curl -fsS --connect-timeout 5 --max-time 30 \
  --user "admin:${grafana_password}" \
  --header 'Host: grafana.cluster-chronicles.local' \
  "http://${cluster_ip}/api/search?type=dash-db")"
printf '%s\n' 'Grafana dashboards:'
python3 -c '
import json, sys
expected = {"Cluster Performance", "Pod and Container Performance", "Application Performance"}
loaded = {item["title"] for item in json.load(sys.stdin)}
print("  " + ", ".join(sorted(expected & loaded)))
missing = expected - loaded
if missing:
    print("Missing Grafana dashboards: " + ", ".join(sorted(missing)), file=sys.stderr)
    sys.exit(1)
' <<<"$grafana_json"

kibana_json="$(curl -fsS --connect-timeout 5 --max-time 30 \
  --header 'Host: kibana.cluster-chronicles.local' \
  --header 'kbn-xsrf: true' \
  "http://${cluster_ip}/api/saved_objects/_find?type=dashboard&per_page=100")"
printf '%s\n' 'Kibana dashboards:'
python3 -c '
import json, sys
expected = {"Cluster Logs Dashboard", "Application Logs Dashboard", "Pod and Container Logs Dashboard"}
loaded = {item["attributes"]["title"] for item in json.load(sys.stdin)["saved_objects"]}
print("  " + ", ".join(sorted(expected & loaded)))
missing = expected - loaded
if missing:
    print("Missing Kibana dashboards: " + ", ".join(sorted(missing)), file=sys.stderr)
    sys.exit(1)
' <<<"$kibana_json"

health_json="$(kubectl get --raw '/api/v1/namespaces/logging/services/http:elasticsearch:9200/proxy/_cluster/health')"
indices_json="$(kubectl get --raw '/api/v1/namespaces/logging/services/http:elasticsearch:9200/proxy/_cat/indices/cluster-logs-*?format=json')"
printf '%s\n' 'Elasticsearch:'
python3 -c '
import json, sys
health = json.loads(sys.argv[1])
indices = json.load(sys.stdin)
documents = sum(int(index.get("docs.count", 0)) for index in indices)
print("  status={}, indices={}, documents={}".format(health["status"], len(indices), documents))
if health["status"] != "green" or not indices or documents < 1:
    sys.exit(1)
' "$health_json" <<<"$indices_json"

printf '%s\n' 'Observability verification passed.'
