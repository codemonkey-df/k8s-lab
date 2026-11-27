#!/usr/bin/env bash
# Tworzy klaster kind "mlops" z osobnym kubeconfigiem.
set -euo pipefail
cd "$(dirname "$0")"
./prereq.sh              # brakujące kind/kubectl/helm → ~/.local/bin; istniejące zostają
source ./env.sh

mkdir -p "$LAB_DATA"/{models,datasets}
chmod -R 0777 "$LAB_DATA"          # Pody działają jako UID 10001
sed "s|\${LAB_DATA}|$LAB_DATA|g" kind-mlops.yaml.tpl > kind-mlops.yaml

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "Klaster $CLUSTER już istnieje — używam go (od zera: ./setup/down.sh && ./setup/up.sh)."
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG" >/dev/null   # odtwórz kubeconfig, gdyby go brakowało
else
  kind create cluster --config kind-mlops.yaml --kubeconfig "$KUBECONFIG"
fi
kubectl get nodes -o wide
echo
echo "Gotowe. W każdym terminalu: source setup/env.sh"
