#!/usr/bin/env bash
# Buduje obraz FTI i ładuje go do węzłów kind (kind nie widzi lokalnego `docker images`).
set -euo pipefail
cd "$(dirname "$0")"
source ../setup/env.sh
TAG="${1:-0.1}"
docker build -t "fti-lab:${TAG}" .
kind load docker-image "fti-lab:${TAG}" --name "$CLUSTER"
echo "OK: fti-lab:${TAG} załadowany do klastra ${CLUSTER}"
