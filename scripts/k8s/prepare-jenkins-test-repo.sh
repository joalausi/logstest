#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "${script_dir}/../.." && pwd)"
test_id="${JENKINS_TEST_ID:-20260801b}"
source_dir="/var/jenkins_home/test-source-${test_id}"
repo_dir="/var/jenkins_home/test-repo-${test_id}.git"
repo_url="file://${repo_dir}"
pod_name="$(kubectl -n ci-cd get pod \
  -l app.kubernetes.io/name=jenkins \
  -o jsonpath='{.items[0].metadata.name}')"

kubectl -n ci-cd exec "$pod_name" -- test ! -e "$source_dir"
kubectl -n ci-cd exec "$pod_name" -- test ! -e "$repo_dir"
kubectl cp "${project_root}/." "ci-cd/${pod_name}:${source_dir}"

kubectl -n ci-cd exec "$pod_name" -- \
  env TEST_SOURCE_DIR="$source_dir" TEST_REPO_DIR="$repo_dir" \
  sh -ec '
    cd "$TEST_SOURCE_DIR"
    git init --initial-branch=cluster-chronicles
    git config user.name Cluster-Chronicles-Test
    git config user.email test@cluster.local
    git add app ci k8s scripts Makefile README.md .gitattributes
    git commit -m pipeline-test
    git clone --bare . "$TEST_REPO_DIR"
  '

kubectl -n ci-cd set env deployment/jenkins --containers=jenkins \
  'JAVA_OPTS=-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true' \
  "JENKINS_GIT_URL=${repo_url}" \
  'JENKINS_GIT_BRANCH=*/cluster-chronicles'
kubectl -n ci-cd rollout status deployment/jenkins --timeout=10m

printf 'Jenkins test repository is ready at %s\n' "$repo_url"
