#!/usr/bin/env bash
# Constroi a imagem Docker com o Sniper compilado e commit fixado.
# Uso: ./scripts/build_image.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_NAME="larc-thermal-sniper:latest"

docker build \
  -f "${REPO_ROOT}/docker/Dockerfile" \
  -t "${IMAGE_NAME}" \
  "${REPO_ROOT}/docker"

echo "Imagem construida: ${IMAGE_NAME}"
