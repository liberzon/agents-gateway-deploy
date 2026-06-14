#!/bin/bash
# Deploy the agents-gateway image to Koyeb pinned to an immutable :<tag>.
#
# The k8s pipeline (docker-build.yml -> deploy-k8s.yml) is the primary path; this
# script is the separate, manual **Koyeb** path. The gateway image is built by
# .github/workflows/docker-build.yml and pushed to GHCR with version + :<sha> +
# :latest tags. koyeb.yaml hardcodes :latest, which is a *moving* tag — so the
# deployed commit can't be read back from Koyeb's control plane.
#
# This pins the Koyeb service to a specific immutable tag instead, so the
# deployment record carries the commit (reported by personal_finance's
# scripts/koyeb_status.py without warming the service).
#
# Usage:
#   ./scripts/koyeb-deploy.sh <tag>     # tag = a git sha or version present in GHCR
#   e.g. ./scripts/koyeb-deploy.sh 1a2b3c4
#
# Env overrides: KOYEB_IMAGE_REPO, KOYEB_APP, KOYEB_SERVICE.
# Requires an authenticated koyeb CLI (`koyeb login`).
set -euo pipefail

TAG="${1:?usage: $0 <image-tag>  (a git sha or version pushed to GHCR; not 'latest')}"
IMAGE_REPO="${KOYEB_IMAGE_REPO:-ghcr.io/liberzon/agents-gateway}"
APP="${KOYEB_APP:-agents-gateway}"
SERVICE="${KOYEB_SERVICE:-gateway}"
IMAGE="${IMAGE_REPO}:${TAG}"

if [ "$TAG" = "latest" ]; then
    echo "Refusing to pin ':latest' — pass an immutable tag (a git sha or version) so the" >&2
    echo "deployed commit stays trackable. See the available tags in GHCR." >&2
    exit 1
fi

command -v koyeb >/dev/null 2>&1 || {
    echo "koyeb CLI not found. Install it and run 'koyeb login' first." >&2
    exit 1
}

echo "Pinning Koyeb service ${APP}/${SERVICE} to ${IMAGE} ..."
koyeb service update "${APP}/${SERVICE}" --docker "${IMAGE}"
echo "Done. Verify:  koyeb service get ${APP}/${SERVICE}"
