# agents-gateway-deploy

**📖 Docs & landing page: [agentsgateway.dev](https://agentsgateway.dev)**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![App Python](https://img.shields.io/badge/Python%20(app)-3.11+-blue.svg)](https://github.com/liberzon/agents-gateway)
[![Image](https://img.shields.io/badge/Image-ghcr.io%2Fliberzon%2Fagents--gateway-2496ED.svg?logo=docker)](https://github.com/liberzon/agents-gateway/pkgs/container/agents-gateway)
[![Source](https://img.shields.io/badge/Source-liberzon%2Fagents--gateway-181717.svg?logo=github)](https://github.com/liberzon/agents-gateway)

Deployment artifacts for [**agents-gateway**](https://github.com/liberzon/agents-gateway) — an AI agents gateway built with FastAPI and Agno. This repo packages everything needed to run it on someone else's infrastructure:

- **One-click platform deploys** to Render, Railway, and Koyeb (image-based, no source build).
- **Kubernetes manifests** for self-hosters running their own cluster.
- **Build pipeline** that publishes the prebuilt image to GHCR.

The app itself lives in [`liberzon/agents-gateway`](https://github.com/liberzon/agents-gateway) — runs on **Python 3.11+** (image base: `python:3.14-slim`). This repo doesn't contain Python; it just deploys the image.

---

## Deploy in one click

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template?template=https://github.com/liberzon/agents-gateway-deploy)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/liberzon/agents-gateway-deploy)
[![Deploy to Koyeb](https://img.shields.io/badge/Deploy%20to-Koyeb-121212?style=for-the-badge&logo=koyeb&logoColor=white)](https://app.koyeb.com/deploy?type=git&repository=github.com/liberzon/agents-gateway-deploy)

All three pull the prebuilt image **`ghcr.io/liberzon/agents-gateway:latest`** (public, multi-arch: `linux/amd64` + `linux/arm64`). You supply DB connection + LLM API key at deploy time; the app boots and exposes the v2 API.

For step-by-step instructions per platform — provisioning Postgres, env vars to set, a curl-based smoke test, costs, and teardown — see **[`DEPLOY_TEST_PLAN.md`](DEPLOY_TEST_PLAN.md)**.

---

## What's in this repo

```
.
├── render.yaml              # Render Blueprint (image-based deploy)
├── koyeb.yaml               # Koyeb service spec (image-based deploy)
├── railway.toml             # Railway config (uses Dockerfile below)
├── Dockerfile               # Thin wrapper: FROM ghcr.io/liberzon/agents-gateway
├── DEPLOY_TEST_PLAN.md      # Per-platform smoke-test playbook
│
├── config/
│   └── projects.yaml        # Image/source/k8s config (drives the build workflow)
│
├── k8s/
│   ├── base/                # Generic Kubernetes manifests (kustomize)
│   └── overlays/
│       └── agents-gateway/  # Per-project customisations
│
└── .github/workflows/
    ├── docker-build.yml     # Build + push multi-platform image to GHCR
    ├── deploy-k8s.yml       # Apply kustomize manifests to a target cluster
    └── sync-upstream.yml    # Periodically rebuild when upstream tags release
```

---

## Architecture

```
┌─────────────────────────────────┐      ┌─────────────────────────────────────────────┐
│  liberzon/agents-gateway        │      │  liberzon/agents-gateway-deploy             │
│  (Source code, MIT)             │      │  (This repository, MIT)                     │
│                                 │      │                                             │
│  • FastAPI + Agno (Python 3.11+)│      │  • config/projects.yaml — image / source   │
│  • Dockerfile                   │◄─────│  • render.yaml / koyeb.yaml / railway.toml │
│  • CI: lint / tests / scans     │      │  • k8s/                — kustomize overlays│
│                                 │      │  • workflows           — build & deploy    │
└─────────────────────────────────┘      └─────────────────────────────────────────────┘
              │                                              │
              │  docker-build.yml builds the image           │
              └──────────────┬───────────────────────────────┘
                             ▼
            ghcr.io/liberzon/agents-gateway:latest  (public)
                             │
        ┌────────────────────┼─────────────────────┐
        ▼                    ▼                     ▼
    Render             Koyeb                Railway / K8s
    (render.yaml)      (koyeb.yaml)         (railway.toml / k8s/)
```

---

## Deploy paths in detail

### 1. One-click platform deploys (recommended for most users)

| Platform | Config | Mechanism |
|---|---|---|
| **Render** | `render.yaml` | `runtime: image`, pulls `ghcr.io/liberzon/agents-gateway:latest` directly. |
| **Koyeb** | `koyeb.yaml` | `docker.image:` pulls the same prebuilt image. Requires Koyeb secrets to be pre-created — see [`DEPLOY_TEST_PLAN.md`](DEPLOY_TEST_PLAN.md). |
| **Railway** | `railway.toml` + `Dockerfile` | Railway's template flow doesn't natively accept image-only deploys, so a thin wrapper `Dockerfile` does `FROM ghcr.io/liberzon/agents-gateway:latest`. The "build" is just an image pull. |

All three default to `PROMPT_STORAGE_BACKEND=postgres`. You'll be prompted to fill DB credentials and at least one LLM API key (Gemini / OpenAI / Anthropic).

### 2. Kubernetes (for self-hosters with their own cluster)

Kustomize-based — base manifests under `k8s/base/` with per-project overlays under `k8s/overlays/`. Deploy:

```bash
gh workflow run deploy-k8s.yml \
  -f project=agents-gateway \
  -f environment=production \
  -f image_tag=latest
```

Requires a `KUBECONFIG_AGENTS_GATEWAY` secret (base64-encoded kubeconfig) — see [Secrets](#kubernetes-secrets) below. For GKE workload-identity auth, see `config/projects.yaml`.

---

## Workflows

### `docker-build.yml` — build & publish image

Multi-platform (linux/amd64 + linux/arm64), pushed to GitHub Container Registry. Triggered by:

- `repository_dispatch` from the app repo (on release)
- `workflow_dispatch` (manual)
- `workflow_call` (from `sync-upstream.yml`)

```bash
gh workflow run docker-build.yml --repo liberzon/agents-gateway-deploy \
  -f project=agents-gateway \
  -f ref=main \
  -f version=0.1.0 \
  -f trigger_deploy=false
```

Publishes to **`ghcr.io/liberzon/agents-gateway`** (public). Tags: `latest`, `<version>`, `<major>.<minor>`, `<major>`, and the source-repo short SHA.

### `deploy-k8s.yml` — kustomize apply

Applies the overlay for a project against the kubeconfig stored in the corresponding secret. Optional — only used by the Kubernetes deploy path.

### `sync-upstream.yml` — daily upstream check

Runs daily; for each project with `sync.enabled: true` in `projects.yaml`, checks for new upstream releases/tags and triggers `docker-build.yml` if there's a new one.

---

## Configuration

### `config/projects.yaml`

Central registry of projects to track and deploy. Each entry declares source, image, build platforms, and Kubernetes target:

```yaml
projects:
  - name: agents-gateway
    source:
      repo: liberzon/agents-gateway
      branch: main
    image:
      registry: ghcr.io
      name: liberzon/agents-gateway
    build:
      platforms:
        - linux/amd64
        - linux/arm64
    kubernetes:
      namespace: agents-gateway
      auth:
        type: kubeconfig
        secretName: KUBECONFIG_AGENTS_GATEWAY
    sync:
      enabled: true
      strategy: releases
```

### Kubernetes secrets

Only required if you use the **Kubernetes deploy path**. Not needed for one-click platform deploys.

| Secret | Description |
|---|---|
| `KUBECONFIG_AGENTS_GATEWAY` | Base64-encoded kubeconfig for the target cluster |
| `DB_PASS_AGENTS_GATEWAY` | Database password (mapped via `envFromSecrets` in `projects.yaml`) |
| `…_AGENTS_GATEWAY` | Other per-project secrets (see `projects.yaml`) |

Setting kubeconfig:

```bash
base64 -w0 ~/.kube/config | gh secret set KUBECONFIG_AGENTS_GATEWAY \
  --repo liberzon/agents-gateway-deploy
```

---

## Adding a new project

This repo is generic-enough to deploy any OSS service that ships a public OCI image. To add one:

1. **`config/projects.yaml`** — add a new entry under `projects:` (mirror the `agents-gateway` block).
2. **Overlay** — `mkdir -p k8s/overlays/<name>` and create a `kustomization.yaml` referencing `../../base`, plus a `namespace.yaml`.
3. **Secrets** — add `KUBECONFIG_<NAME>` (and any app secrets) for that project.
4. **Run** — `gh workflow run docker-build.yml -f project=<name>`.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `docker-build.yml` fails at "Parse project configuration" → `Project 'X' not found` | `name` in `projects.yaml` doesn't match the workflow input `project=` |
| Build job reports `invalid tag "/agents-gateway:..."` | (Was a real bug — see commit `71181c0`. If it recurs, check that `image.registry` and `image.name` in `projects.yaml` are non-empty.) |
| Image push succeeds but `trigger-deploy` fails with `Resource not accessible by integration` | The default `GITHUB_TOKEN` lacks `actions:write`. Only matters for the K8s path; harmless for one-click deploys. |
| One-click deploy gets 500 on `/v2/agents/<id>/chat` | First boot may take longer than the platform's health timeout. Try a second chat. Persistent — pull `docker logs` and open an issue on [agents-gateway](https://github.com/liberzon/agents-gateway/issues). |
| `/health` 404s | Service hasn't finished booting; or you've set the wrong port. Render/Koyeb already use the right port; Railway uses `$PORT`. |
| Pod `CrashLoopBackOff` on K8s | Inspect logs: `kubectl logs -n agents-gateway -l app.kubernetes.io/name=agents-gateway`. Most common cause: missing DB creds. |

---

## License

[MIT](LICENSE) — the app source code in [`liberzon/agents-gateway`](https://github.com/liberzon/agents-gateway) is also MIT.
