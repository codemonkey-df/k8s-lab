#!/usr/bin/env bash
# Tworzy klaster kind "mlops" z osobnym kubeconfigiem.
set -euo pipefail
cd "$(dirname "$0")"
source ./env.sh

mkdir -p "$LAB_DATA"/{models,datasets}
chmod -R 0777 "$LAB_DATA"          # Pody działają jako UID 10001
envsubst '${LAB_DATA}' < kind-mlops.yaml.tpl > kind-mlops.yaml

if kind get clusters | grep -qx "$CLUSTER"; then
  echo "Klaster $CLUSTER już istnieje."
else
  kind create cluster --config kind-mlops.yaml --kubeconfig "$KUBECONFIG"
fi
kubectl get nodes -o wide
echo
echo "Gotowe. W każdym terminalu: source setup/env.sh"
