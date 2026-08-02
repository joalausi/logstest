#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../.." && pwd)"
profile_name="${MINIKUBE_PROFILE:-cluster-chronicles}"
registry_port="${REGISTRY_NODE_PORT:-30500}"
registry_ip="$(minikube --profile "$profile_name" ip)"
registry="${registry_ip}:${registry_port}"
node_config_dir="/etc/containerd/certs.d/${registry}"
node_temp_file="/home/docker/cluster-chronicles-registry-hosts.toml"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

sed "s|__REGISTRY__|${registry}|g" \
  "${project_root}/k8s/config/registry-hosts.toml" \
  > "${temp_dir}/hosts.toml"

docker cp "${temp_dir}/hosts.toml" "${profile_name}:${node_temp_file}"
minikube --profile "$profile_name" ssh -- \
  sudo mkdir -p "$node_config_dir"
minikube --profile "$profile_name" ssh -- \
  sudo install -m 0644 "$node_temp_file" "${node_config_dir}/hosts.toml"
minikube --profile "$profile_name" ssh -- \
  sudo systemctl restart containerd

kubectl wait --for=condition=Ready nodes --all --timeout=5m
printf 'Containerd registry endpoint configured: http://%s\n' "$registry"
