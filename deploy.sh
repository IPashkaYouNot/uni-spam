#!/usr/bin/env bash

# Setting the locale to C
export LC_ALL=C

# Behave safe
set -euf -o pipefail

# Settings
ARGOCD_PATH="argocd"
HELM_ARGOCD_REPO="https://argoproj.github.io/argo-helm"
HELM_ARGOCD_VERSION="9.1.0"

# Variables
# Full directory name of the script. https://stackoverflow.com/a/246128/7465844
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# Script name without path
MY_NAME="${0##*/}"

# Session ID
SESSION_ID="$(date +'%Y%m%d%H%M%S%Z')"
# Log file
SESSION_LOG="sc-${SESSION_ID}.log"

# Colours
C_RED='\033[0;31m'
C_GRN='\033[0;32m'
C_YEL='\033[1;33m'
C_BLU='\033[1;34m'
C_NOC='\033[0m'
readonly C_RED C_GRN C_YEL C_BLU C_NOC

# Logging
# Send stdout and stderr output into the log file.
# Leave fd 3 connected to the console, to be able to
#   - write a message just to the console - '1>&3'
#   - to write a message to both the console and the log file - '| tee /dev/fd/3'
exec 3>&1 1>"${SESSION_LOG}" 2>&1

# Print error message to stderr and exit with status code 1.
# Arguments:
#   Error message
function fail() {
  echo -e "[${C_YEL}$(date +'%Y-%m-%dT%H:%M:%S%z')${C_NOC}] ${MY_NAME}: $*" | tee /dev/fd/3 >&2
  exit 1
}

# Print green coloured output.
# Arguments:
#   Message
function log() {
  echo -e "[${C_YEL}$(date +'%Y-%m-%dT%H:%M:%S%z')${C_NOC}] $*" >&1 | tee /dev/fd/3
}

# Perform preliminary (preflight) checks to determine if all prerequisites matched.
function preflight_checks() {
  local func_name="${FUNCNAME[0]}"
  log "${func_name} ${C_BLU}Starting preflight checks...${C_NOC}"

  # Bash version matches
  log "${func_name} ${C_GRN}Checking Bash version...${C_NOC}"
  local bash_version
  bash_version=$(echo "${BASH_VERSION}" | awk -F. '{ print $1$2 }')
  if [[ "$bash_version" -lt 44 ]]; then
    fail "${C_RED}Bash version is lower than 4.4: ${BASH_VERSION} (${bash_version})${C_NOC}"
  fi

  # Tools are available
  log "${func_name} ${C_GRN}Checking if tools are available...${C_NOC}"
  local -ar tools=(helm kubectl minikube docker)
  local -a errors=()
  for t in "${tools[@]}"; do
    if ! command -v "${t}" >/dev/null 2>&1; then
      errors+=("$t")
    fi
  done
  if [[ ${#errors[@]} -ne 0 ]]; then
    fail "${C_RED}Cannot run some of the tools: '${errors[*]}'${C_NOC}"
  fi
}

# Start the minikube cluster
# Globals:
#   BASE_DIR
#   ARGOCD_PATH
function minikube_start() {
  local func_name="${FUNCNAME[0]}"
  log "${func_name} ${C_BLU}Starting and configuring the minikube cluster...${C_NOC}"

  log "${func_name} Starting the minikube cluster"
  minikube start --memory 8192 --addons metrics-server -n 2

  log "${func_name} Waiting 30 seconds for the minikube to be configured${C_NOC}"
  sleep 30

  log "${func_name} Tainting the control plane node"
  kubectl taint nodes minikube node-role.kubernetes.io/master:NoSchedule
}

# ArgoCD installation.
# Globals:
#   BASE_DIR
#   HELM_ARGOCD_REPO
#   HELM_ARGOCD_VERSION
function argocd_installation() {
  local func_name="${FUNCNAME[0]}"
  log "${func_name} ${C_YEL}Deploying ArgoCD...${C_NOC}"

  log "${func_name} ${C_BLU}Installing Argo CD${C_NOC}"
  log "${func_name} Adding Argo CD Helm repository ${HELM_ARGOCD_REPO}"
  if ! helm repo add argo "${HELM_ARGOCD_REPO}" --force-update; then
    fail "${func_name} Unable to add Argo CD Helm repo ${HELM_ARGOCD_REPO}"
  fi

  log "${func_name} Installing Argo CD Helm Chart ${HELM_ARGOCD_VERSION}."
  if ! helm upgrade argo-cd argo/argo-cd --version "${HELM_ARGOCD_VERSION}" --install --namespace argo-cd --create-namespace; then
    fail "${func_name} Unable to install Argo CD Helm Chart ${HELM_ARGOCD_VERSION}"
  fi

  log "${func_name} Waiting 60 seconds for the Argo CD to start${C_NOC}"
  sleep 60

  log "${func_name} Checking Argo CD initial password to be created${C_NOC}"
  if ! kubectl -n argo-cd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'; then
    fail "${func_name} Cannot read Argo CD initial password secret"
  fi
}

# Configure and Deploy Argo CD applications
# Globals:
#   BASE_DIR
#   ARGOCD_PATH
function argocd_applications_installation() {
  local func_name="${FUNCNAME[0]}"
  log "${func_name} ${C_BLU}Installing Argo CD applications...${C_NOC}"

  # Run in subshell to avoid changing directory back
  (
    log "${func_name} Running in ${ARGOCD_PATH}"
    cd "${ARGOCD_PATH}"

    log "${func_name} Deploying Argo CD project"
    kubectl apply -f manifests/argocd-project.yaml

    log "${func_name} Deploying Argo CD manifests Application"
    kubectl apply -f ./manifests.yaml

    kubectl -n argo-cd patch Application "manifests" --patch-file ApplicationManuallySyncPatch.yaml --type merge

    log "${func_name} Waiting 30 seconds for the Namespaces to be created${C_NOC}"
    sleep 30

    log "${func_name} ${C_GRN}Deploying Argo CD Apps one by one"
    find ./applications -name 'application*.yaml' -type f -print0 | xargs -0 -n 1 -t -x kubectl apply -f
    sleep 10

    log "${func_name} Applying initial Argo CD Apps sync"
    while read app
    do
      kubectl -n argo-cd patch Application "${app}" --patch-file ApplicationManuallySyncPatch.yaml --type merge
    done < <(kubectl -n argo-cd get Application --no-headers | awk '{print $1}')
    sleep 10

    log "${func_name} Waiting 30 seconds for the Grafana Namespace to be created${C_NOC}"
    sleep 30

    log "${func_name} ${C_GRN}Deploying Grafana dashboards configmap${C_NOC}"
    kubectl -n grafana create configmap grafana-dashboards-kubernetes \
      --from-file=./applications/values/grafana-dashboards \
      --dry-run=client --save-config -o yaml |
      kubectl apply --server-side=true --force-conflicts -f -
  )
}

log "${C_BLU}Starting, session id: ${C_GRN}${SESSION_ID}${C_NOC}${C_BLU}, logging to ${C_GRN}${SESSION_LOG}${C_NOC}"
preflight_checks
minikube_start
argocd_installation
argocd_applications_installation
log "${C_BLU}Done, session id: ${C_GRN}${SESSION_ID}${C_NOC}${C_BLU}, logged to ${C_GRN}${SESSION_LOG}${C_NOC}"
