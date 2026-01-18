# Multi-Project Kubernetes Deployment Platform

A vendor-agnostic, multi-project deployment platform for OSS projects. Tracks upstream repositories, builds Docker images, and deploys to any Kubernetes cluster.

## Architecture

```
┌─────────────────────────────────┐      ┌─────────────────────────────────────────────┐
│  PUBLIC: agents-gateway         │      │  PRIVATE: agents-gateway-deploy             │
│  (Open Source Code)             │      │  (This Repository)                          │
│                                 │      │                                             │
│  - Source code                  │◄─────│  config/projects.yaml  - Project registry  │
│  - Dockerfile                   │      │  k8s/base/             - Base manifests    │
│  - CI (lint/test only)          │      │  k8s/overlays/         - Per-project config│
│  - No secrets/credentials       │      │  .github/workflows/    - CI/CD pipelines   │
│                                 │      │                                             │
└─────────────────────────────────┘      └─────────────────────────────────────────────┘
```

## Features

- **Multi-Project Support**: Track and deploy multiple OSS projects from a single repository
- **Vendor-Agnostic Kubernetes**: Deploy to any K8s cluster (GKE, EKS, AKS, on-prem)
- **Flexible Authentication**: Kubeconfig or cloud-native auth (GKE Workload Identity)
- **Kustomize-based Deployments**: Base manifests with per-project overlays
- **Automated Sync**: Daily checks for upstream releases with parallel processing
- **Multi-Platform Builds**: amd64 and arm64 Docker images

## Project Configuration

Projects are defined in `config/projects.yaml`:

```yaml
projects:
  - name: agents-gateway
    source:
      repo: liberzon/agents-gateway
      branch: main
    image:
      registry: ghcr.io
      name: liberzon/agents-gateway
    kubernetes:
      namespace: agents-gateway
      auth:
        type: kubeconfig                    # or: gke, eks, aks
        secretName: KUBECONFIG_AGENTS_GATEWAY
      envFromSecrets:
        DB_USER: DB_USER_AGENTS_GATEWAY     # Maps env var to GitHub secret
    sync:
      enabled: true
      strategy: releases                    # or: tags, commits
```

## Workflows

### 1. Sync Upstream (`sync-upstream.yml`)

Monitors all projects for new releases.

```bash
# Check all projects
gh workflow run sync-upstream.yml

# Check specific project
gh workflow run sync-upstream.yml -f project=agents-gateway
```

**Triggers:**
- Daily at 6 AM UTC (scheduled)
- Manual dispatch

### 2. Docker Build (`docker-build.yml`)

Builds and pushes multi-platform Docker images.

```bash
gh workflow run docker-build.yml \
  -f project=agents-gateway \
  -f ref=v1.0.0 \
  -f version=1.0.0 \
  -f trigger_deploy=true
```

**Publishes to:**
- GitHub Container Registry: `ghcr.io/<owner>/<project>`
- Docker Hub: `<username>/<project>`

### 3. Deploy to Kubernetes (`deploy-k8s.yml`)

Deploys to any Kubernetes cluster using kustomize.

```bash
gh workflow run deploy-k8s.yml \
  -f project=agents-gateway \
  -f environment=production \
  -f image_tag=1.0.0
```

## Directory Structure

```
.
├── config/
│   └── projects.yaml           # Central project configuration
├── k8s/
│   ├── base/                   # Base Kubernetes manifests
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── overlays/
│       └── agents-gateway/     # Per-project customizations
│           ├── kustomization.yaml
│           └── namespace.yaml
└── .github/workflows/
    ├── sync-upstream.yml       # Multi-project sync
    ├── docker-build.yml        # Parameterized builds
    └── deploy-k8s.yml          # K8s deployment
```

## Setup Instructions

### 1. Configure GitHub Secrets

#### Docker Registry
| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

#### Per-Project Kubernetes Auth (Kubeconfig method)
| Secret | Description |
|--------|-------------|
| `KUBECONFIG_AGENTS_GATEWAY` | Base64-encoded kubeconfig |

#### Per-Project Application Secrets
| Secret | Description |
|--------|-------------|
| `DB_USER_AGENTS_GATEWAY` | Database username |
| `DB_PASS_AGENTS_GATEWAY` | Database password |
| `DB_HOST_AGENTS_GATEWAY` | Database host |
| ... | (other secrets as defined in projects.yaml) |

### 2. Add a New Project

1. **Add to projects.yaml:**
   ```yaml
   projects:
     - name: my-new-project
       source:
         repo: org/my-new-project
         branch: main
       image:
         registry: ghcr.io
         name: org/my-new-project
       kubernetes:
         namespace: my-new-project
         auth:
           type: kubeconfig
           secretName: KUBECONFIG_MY_NEW_PROJECT
       sync:
         enabled: true
         strategy: releases
   ```

2. **Create overlay directory:**
   ```bash
   mkdir -p k8s/overlays/my-new-project
   ```

3. **Create kustomization.yaml:**
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   resources:
     - ../../base
     - namespace.yaml
   namespace: my-new-project
   namePrefix: my-new-project-
   images:
     - name: placeholder
       newName: ghcr.io/org/my-new-project
       newTag: latest
   ```

4. **Add GitHub secrets** for the new project

### 3. Kubernetes Authentication Methods

#### Kubeconfig (Any Cluster)

```yaml
kubernetes:
  auth:
    type: kubeconfig
    secretName: KUBECONFIG_MY_PROJECT  # Base64-encoded kubeconfig
```

Generate the secret:
```bash
base64 -w0 ~/.kube/config | gh secret set KUBECONFIG_MY_PROJECT
```

#### GKE Native Auth

```yaml
kubernetes:
  auth:
    type: gke
    project: my-gcp-project
    cluster: my-cluster
    region: us-central1
    serviceAccountKey: GCP_SA_KEY_MY_PROJECT
```

## Triggering from Public Repo

Add this workflow to your public repo to trigger deployments on release:

```yaml
# .github/workflows/release.yml
name: Release

on:
  release:
    types: [published]

jobs:
  notify-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger deployment repo
        uses: peter-evans/repository-dispatch@v2
        with:
          token: ${{ secrets.DEPLOY_REPO_TOKEN }}
          repository: your-org/agents-gateway-deploy
          event-type: upstream-release
          client-payload: |
            {
              "project": "agents-gateway",
              "ref": "${{ github.ref }}",
              "version": "${{ github.event.release.tag_name }}"
            }
```

## Security Notes

- Never commit secrets to this repository
- Use GitHub Secrets for all sensitive values
- Per-project secret naming convention: `SECRET_NAME_PROJECT_NAME`
- Keep this repository private
- Rotate credentials regularly

## Troubleshooting

### Build fails with "Project not found"
- Verify the project name exists in `config/projects.yaml`
- Check YAML syntax with `yq e '.' config/projects.yaml`

### Kubernetes deployment fails
- Verify kubeconfig secret is base64-encoded
- Test cluster connectivity: `kubectl cluster-info`
- Check namespace exists or can be created

### Sync doesn't detect new releases
- Verify `sync.enabled: true` in projects.yaml
- Check GitHub API rate limits
- Ensure upstream repo has published releases (not just tags)

### Health check fails
- Verify the application exposes `/health` endpoint
- Check container logs: `kubectl logs -n <namespace> -l app.kubernetes.io/name=<project>`
- Verify resource limits are sufficient

