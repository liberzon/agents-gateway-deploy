# agents-gateway-deploy

Private deployment repository for [agents-gateway](https://github.com/your-org/agents-gateway).

This repository contains deployment workflows and configurations that are kept separate from the public open-source repository for security reasons.

## Architecture

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│  PUBLIC: agents-gateway         │      │  PRIVATE: agents-gateway-deploy │
│  (Open Source Code)             │      │  (This Repository)              │
│                                 │      │                                 │
│  - Source code                  │◄─────│  - docker-publish.yml           │
│  - Dockerfile                   │      │  - deploy-gcp.yml               │
│  - CI (lint/test only)          │      │  - sync-upstream.yml            │
│  - No secrets/credentials       │      │  - All deployment secrets       │
│                                 │      │                                 │
└─────────────────────────────────┘      └─────────────────────────────────┘
```

## Workflows

### 1. Docker Publish (`docker-publish.yml`)

Builds and publishes Docker images to:
- **GitHub Container Registry**: `ghcr.io/<owner>/agents-gateway`
- **Docker Hub**: `<username>/agents-gateway`

**Triggers:**
- `repository_dispatch` - From public repo releases
- `workflow_dispatch` - Manual trigger with version input

**Tags generated:**
- Semantic version (e.g., `1.0.0`, `1.0`, `1`)
- `latest` (for main branch)
- Git SHA

### 2. Deploy GCP (`deploy-gcp.yml`)

Deploys to Google Cloud Run.

**Triggers:**
- After `docker-publish` workflow completes
- Manual trigger with environment selection

**Environments:**
- `development` → `dev-agents-gateway`
- `staging` → `staging-agents-gateway`
- `production` → `agents-gateway`

### 3. Sync Upstream (`sync-upstream.yml`)

Checks for new releases in the public repo.

**Triggers:**
- Daily at 6 AM UTC
- Manual trigger

## Setup Instructions

### 1. Create Repository Secrets

Go to Settings → Secrets and variables → Actions, and add:

#### Docker Registry Secrets
| Secret | Description |
|--------|-------------|
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

#### GCP Deployment Secrets
| Secret | Description |
|--------|-------------|
| `GCP_PROJECT_ID` | Google Cloud project ID |
| `GCP_SERVICE_ACCOUNT_KEY` | Service account JSON key |
| `GCP_SERVICE_ACCOUNT` | Service account email |
| `VPC_CONNECTOR` | VPC connector name (optional) |

#### Application Secrets
| Secret | Description |
|--------|-------------|
| `DB_USER` | Database username |
| `DB_PASS` | Database password |
| `DB_HOST` | Database host |
| `DB_PORT` | Database port (usually 5432) |
| `DB_DATABASE` | Database name |
| `SERVICE_PROMPTS` | Prompts service URL |
| `GOOGLE_API_KEY` | Google API key for Gemini |
| `QDRANT_URL` | Qdrant vector database URL |
| `QDRANT_API_KEY` | Qdrant API key |
| `SECRET_TOKEN_ENC_KEY` | Fernet encryption key |

### 2. Update Workflow Configuration

Edit the workflows to update:

1. **`docker-publish.yml`**: Update `SOURCE_REPO` with your public repo path
2. **`sync-upstream.yml`**: Update `SOURCE_REPO` with your public repo path

### 3. Create Docker Hub Repository

1. Go to [Docker Hub](https://hub.docker.com)
2. Create a new repository named `agents-gateway`
3. Generate an access token for CI/CD

### 4. Enable GitHub Container Registry

GHCR is enabled by default for GitHub organizations. The first push will create the package.

## Manual Deployment

### Build and Push Docker Image

```bash
# Trigger via GitHub Actions UI
# Go to Actions → Build and Publish Docker Images → Run workflow

# Or use GitHub CLI
gh workflow run docker-publish.yml -f ref=main -f version=1.0.0
```

### Deploy to Cloud Run

```bash
# Trigger via GitHub Actions UI
# Go to Actions → Deploy to Google Cloud Run → Run workflow

# Or use GitHub CLI
gh workflow run deploy-gcp.yml -f environment=development -f image_tag=latest
```

## Image Locations

After publishing, images are available at:

```bash
# GitHub Container Registry
docker pull ghcr.io/<owner>/agents-gateway:latest
docker pull ghcr.io/<owner>/agents-gateway:1.0.0

# Docker Hub
docker pull <username>/agents-gateway:latest
docker pull <username>/agents-gateway:1.0.0
```

## Triggering from Public Repo

To trigger a build from the public repo on release:

```yaml
# In public repo: .github/workflows/release.yml
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
          client-payload: '{"ref": "${{ github.ref }}", "version": "${{ github.event.release.tag_name }}"}'
```

## Security Notes

- Never commit secrets to this repository
- Use GitHub Secrets for all sensitive values
- Rotate credentials regularly
- Review workflow runs for any exposed secrets
- Keep this repository private

## Troubleshooting

### Build fails with "unauthorized"
- Verify `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are set correctly
- Ensure Docker Hub token has write permissions

### Deploy fails with "permission denied"
- Verify `GCP_SERVICE_ACCOUNT_KEY` contains valid JSON
- Ensure service account has Cloud Run Admin role
- Check VPC connector permissions if using private networking

### Sync doesn't detect new releases
- Verify `SOURCE_REPO` is set correctly in workflow
- Check GitHub API rate limits
- Ensure public repo has published releases (not just tags)