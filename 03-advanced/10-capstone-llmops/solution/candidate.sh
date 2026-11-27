#!/usr/bin/env bash
# Kandydat vN obok stable: ./candidate.sh v4 ; potem route-shadow.yaml -> route-canary.yaml -> ./release.sh v4
set -euo pipefail
V=${1:?wersja, np. v4}
cd "$(dirname "$0")"
sed "s/__VERSION__/$V/g" candidate.yaml | kubectl apply -f - >/dev/null
kubectl -n ml rollout status deploy/inference-candidate
