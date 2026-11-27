#!/usr/bin/env bash
# Promocja vN na stable: release.env -> kubectl apply -k (nowy hash ConfigMap = rollout) + change-cause.
set -euo pipefail
V=${1:?wersja, np. v4}
cd "$(dirname "$0")"
test -n "$(kubectl -n ml get job "train-$V" -o jsonpath='{.status.succeeded}' 2>/dev/null)" \
  || { echo "train-$V nie przeszedł bramki (albo nie istnieje) — nie promuję"; exit 1; }
ACC=$(kubectl -n ml logs "job/train-$V" | grep -o 'accuracy=[0-9.]*' | tail -1)
echo "MODEL_VERSION=$V" > platform/release.env
kubectl apply -k platform >/dev/null
kubectl -n ml annotate deploy inference kubernetes.io/change-cause="model $V ($ACC)" --overwrite >/dev/null
kubectl -n ml rollout status deploy/inference
kubectl -n ml delete -f candidate.yaml --ignore-not-found >/dev/null 2>&1 || true
