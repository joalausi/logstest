#!/usr/bin/env bash
set -euo pipefail

profile="${MINIKUBE_PROFILE:-cluster-chronicles}"
job_name="${JENKINS_JOB_NAME:-cluster-chronicles-deploy}"
cluster_ip="$(minikube -p "$profile" ip)"
jenkins_url="http://${cluster_ip}"
jenkins_host="jenkins.cluster-chronicles.local"
jenkins_user="admin"
jenkins_password="$(kubectl -n ci-cd get secret jenkins-admin -o jsonpath='{.data.password}' | base64 -d)"
cookie_jar="$(mktemp)"
trap 'rm -f "$cookie_jar"' EXIT

jenkins_get() {
  curl --globoff --fail --silent --show-error \
    --user "${jenkins_user}:${jenkins_password}" \
    --cookie "$cookie_jar" \
    --cookie-jar "$cookie_jar" \
    --header "Host: ${jenkins_host}" \
    "${jenkins_url}$1"
}

printf 'Checking Jenkins job API\n'
job_json="$(jenkins_get "/job/${job_name}/api/json?tree=nextBuildNumber,property[parameterDefinitions[name]]")"
build_number="$(printf '%s' "$job_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["nextBuildNumber"])')"
is_parameterized="$(printf '%s' "$job_json" | python3 -c 'import json,sys; print(str(any(p.get("parameterDefinitions") for p in json.load(sys.stdin).get("property", []))).lower())')"
printf 'Requesting Jenkins CSRF crumb\n'
crumb_json="$(jenkins_get '/crumbIssuer/api/json')"
crumb_field="$(printf '%s' "$crumb_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["crumbRequestField"])')"
crumb_value="$(printf '%s' "$crumb_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["crumb"])')"

if [ -n "${JENKINS_STOP_BUILD:-}" ]; then
  printf 'Stopping Jenkins build #%s\n' "$JENKINS_STOP_BUILD"
  curl --fail --silent --show-error \
    --request POST \
    --user "${jenkins_user}:${jenkins_password}" \
    --cookie "$cookie_jar" \
    --cookie-jar "$cookie_jar" \
    --header "Host: ${jenkins_host}" \
    --header "${crumb_field}: ${crumb_value}" \
    "${jenkins_url}/job/${job_name}/${JENKINS_STOP_BUILD}/stop" >/dev/null
  exit
fi

printf 'Triggering Jenkins build #%s\n' "$build_number"
build_endpoint="/job/${job_name}/build"
if [ "$is_parameterized" = true ]; then
  build_endpoint="/job/${job_name}/buildWithParameters?ROLLBACK_TAG=${JENKINS_ROLLBACK_TAG:-}"
fi
curl --fail --silent --show-error \
  --request POST \
  --user "${jenkins_user}:${jenkins_password}" \
  --cookie "$cookie_jar" \
  --cookie-jar "$cookie_jar" \
  --header "Host: ${jenkins_host}" \
  --header "${crumb_field}: ${crumb_value}" \
  "${jenkins_url}${build_endpoint}" >/dev/null

printf 'Triggered Jenkins build #%s\n' "$build_number"

for _ in $(seq 1 120); do
  if build_json="$(jenkins_get "/job/${job_name}/${build_number}/api/json" 2>/dev/null)"; then
    building="$(printf '%s' "$build_json" | python3 -c 'import json,sys; print(str(json.load(sys.stdin)["building"]).lower())')"
    result="$(printf '%s' "$build_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"] or "RUNNING")')"
    printf 'Build #%s: %s\n' "$build_number" "$result"
    if [ "$building" = false ]; then
      jenkins_get "/job/${job_name}/${build_number}/consoleText"
      [ "$result" = SUCCESS ]
      exit
    fi
  else
    printf 'Build #%s is queued\n' "$build_number"
  fi
  sleep 15
done

printf 'Timed out waiting for Jenkins build #%s\n' "$build_number" >&2
jenkins_get "/job/${job_name}/${build_number}/consoleText" || true
exit 1
