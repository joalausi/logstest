#!/usr/bin/env bash
set -euo pipefail

profile_name="${MINIKUBE_PROFILE:-cluster-chronicles}"
cluster_cpus="${MINIKUBE_CPUS:-4}"
cluster_memory="${MINIKUBE_MEMORY:-10500mb}"
cluster_disk="${MINIKUBE_DISK:-80g}"
binary_dir="${HOME}/.local/bin"

log() {
  printf '==> [cluster-bootstrap] %s\n' "$*"
}

install_minikube() {
  if command -v minikube >/dev/null 2>&1; then
    return
  fi

  log "Installing Minikube in ${binary_dir}"
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN
  curl -fsSLo "${temp_dir}/minikube" \
    https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  curl -fsSLo "${temp_dir}/minikube.sha256" \
    https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64.sha256
  printf '%s  %s\n' "$(tr -d '[:space:]' < "${temp_dir}/minikube.sha256")" "${temp_dir}/minikube" \
    | sha256sum --check
  install -m 0755 "${temp_dir}/minikube" "${binary_dir}/minikube"
  rm -rf "$temp_dir"
  trap - RETURN
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    return
  fi

  log "Installing kubectl in ${binary_dir}"
  kubectl_version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' RETURN
  curl -fsSLo "${temp_dir}/kubectl" \
    "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"
  curl -fsSLo "${temp_dir}/kubectl.sha256" \
    "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl.sha256"
  printf '%s  %s\n' "$(tr -d '[:space:]' < "${temp_dir}/kubectl.sha256")" "${temp_dir}/kubectl" \
    | sha256sum --check
  install -m 0755 "${temp_dir}/kubectl" "${binary_dir}/kubectl"
  rm -rf "$temp_dir"
  trap - RETURN
}

mkdir -p "$binary_dir"
export PATH="${binary_dir}:${PATH}"

command -v docker >/dev/null 2>&1 || {
  echo "Docker is required before Minikube can use the docker driver." >&2
  exit 1
}
docker info >/dev/null

install_minikube
install_kubectl

log "Starting Minikube profile ${profile_name}"
minikube start \
  --profile "$profile_name" \
  --driver docker \
  --container-runtime containerd \
  --cpus "$cluster_cpus" \
  --memory "$cluster_memory" \
  --disk-size "$cluster_disk" \
  --insecure-registry "192.168.0.0/16" \
  --cni calico \
  --addons ingress,metrics-server,storage-provisioner,default-storageclass

minikube profile "$profile_name"
bash "${script_dir}/configure-registry.sh"
kubectl wait --for=condition=Ready nodes --all --timeout=5m

log "Cluster is ready"
minikube status --profile "$profile_name"
kubectl get nodes -o wide
