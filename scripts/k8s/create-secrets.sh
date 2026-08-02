#!/usr/bin/env bash
set -euo pipefail

credentials_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/cluster-chronicles"
credentials_file="${credentials_dir}/credentials.env"

mkdir -p "$credentials_dir"
chmod 0700 "$credentials_dir"

if [[ ! -f "$credentials_file" ]]; then
  umask 077
  {
    printf 'JENKINS_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 16)"
    printf 'GRAFANA_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 16)"
  } > "$credentials_file"
fi

chmod 0600 "$credentials_file"
set -a
# shellcheck disable=SC1090
source "$credentials_file"
set +a

kubectl -n ci-cd create secret generic jenkins-admin \
  --from-literal="password=${JENKINS_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n observability create secret generic grafana-admin \
  --from-literal="password=${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

printf 'Credentials are stored with mode 0600 in %s\n' "$credentials_file"
