# Thin wrapper used by one-click platforms that build from a Dockerfile
# (Railway). Render and Koyeb pull the prebuilt image directly via
# render.yaml / koyeb.yaml -- they don't need this file.
#
# The actual app image is built by .github/workflows/docker-build.yml
# from the liberzon/agents-gateway source repo and published to GHCR.
FROM ghcr.io/liberzon/agents-gateway:latest
