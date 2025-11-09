# Spam Monitoring Stack

This repository provides a GitOps-based monitoring and deployment stack for the custom Spam application and its observability components.
Everything is managed through Argo CD, with automated deployment scripts and custom Grafana dashboards for visualizing application and cluster metrics.

---

## Repository Structure

- argocd/manifests.yaml - Argo CD root manifest for deploying all resources
- argocd/manifests/ - Supporting manifests
- argocd/manifests/argocd-project.yaml
- argocd/manifests/namespaces.yaml
- argocd/applications/ - Argo CD Application definitions
- argocd/applications/application-argocd.yaml
- argocd/applications/application-grafana.yaml
- argocd/applications/application-spam.yaml
- argocd/applications/application-victoria-metrics-agent.yaml
- argocd/applications/application-victoria-metrics-cluster.yaml
- argocd/values/ - Helm values for each application
- argocd/grafana-dashboards/ - Custom Grafana dashboards
- argocd/ApplicationManuallySyncPatch.yaml - Used by scripts to trigger manual sync
- helm-charts/spam - Custom Helm chart for the Spam application
- deploy.sh - Main deployment script

---

## Overview

The stack consists of:

- Spam application — a sample service that produces random Prometheus-compatible metrics and logs.
- Grafana — visualization and dashboarding.
- VictoriaMetrics Cluster — scalable metrics storage backend.
- VictoriaMetrics Agent — metrics scraper and forwarder.
- Argo CD — GitOps controller managing all deployments.

---

## Deployment Process

All deployments are handled through the `deploy.sh` script, which encapsulates the full local setup flow.

### Script Functions

| Function                           | Description                                                                                                                                 |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `preflight_checks`                 | Verifies system prerequisites: Bash ≥ 4.4 and tools (`helm`, `kubectl`, `minikube`, `docker`).                                              |
| `minikube_start`                   | Starts a local Minikube Kubernetes cluster.                                                                                                 |
| `argocd_installation`              | Installs the initial Argo CD instance via Helm.                                                                                             |
| `argocd_applications_installation` | Creates all Argo CD `Application` resources (Spam, Grafana, VictoriaMetrics Agent, VictoriaMetrics Cluster) and applies Grafana dashboards. |

The script uses Argo CD to apply all manifests from `argocd/` and to trigger manual synchronization via:

```yaml
# argocd/ApplicationManuallySyncPatch.yaml
operation:
  initiatedBy:
    username: admin
  sync:
    syncStrategy:
      hook: {}
```

Autosync is disabled, so applications are synced explicitly by the script.

## Grafana Dashboards

Located under argocd/grafana-dashboards/.

### ArgoCD Dashboards

- ArgoCD-Applications-Dashboard.json — health, sync status, and deployment progress of Argo CD applications.
- ArgoCD-Operational-Dashboard.json — operational metrics for Argo CD components (API server, repo-server, etc.).

### Kubernetes Dashboards

- Kubernetes-Cluster.json - most kubernetes-related metrics

### Spam Dashboards

- Spam-RandomGauge.json - for each random gauge metrics exposed by the Spam app has total active sessions, active sessions by platform and by country
- Spam-NameGauge.json - data based on name_gauge: Average Performance per Job and Average Total Performance
- Spam-Histogram.json - histogram-based latency metrics (with le), average sum and count over 1 hour

### Victoria Metrics Dashboards

- VM-Agent.json - agent related metrics
- VM-Cluster.json - cluster related metrics

## How to deploy locally

### Prerequisites

- [Git](https://git-scm.com/downloads)
- [Docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Minikube](https://minikube.sigs.k8s.io/docs/start/)

```sh
git clone https://github.com/IPashkaYouNot/uni-spam.git
cd uni-spam

./deploy.sh
```

This script will verify the environment, start a local Minikube cluster, install Argo CD via Helm, deploy Spam, Grafana, VictoriaMetrics agent and cluster, and load dashboards.

To access the Grafana UI, retrieve the admin password:

```sh
kubectl -n grafana get secret grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

and make a port-forward to the Grafana service:

```sh
kubectl -n grafana port-forward svc/grafana 3000:80
```

Then you can access the Grafana UI at [http://localhost:3000](http://localhost:3000) with the admin password.

To access the ArgoCD UI, retrieve the admin password:

```sh
kubectl -n argo-cd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

and make a port-forward to the ArgoCD service:

```sh
kubectl -n argo-cd port-forward svc/argo-cd-argocd-server 8080:443
```

Then you can access the ArgoCD UI at [http://localhost:8080](http://localhost:8080) with the admin password.
