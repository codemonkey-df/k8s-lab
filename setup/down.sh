#!/usr/bin/env bash
# Usuwa klaster labowy (dane w $LAB_DATA zostają).
set -euo pipefail
source "$(dirname "$0")/env.sh"
kind delete cluster --name "$CLUSTER" --kubeconfig "$KUBECONFIG"
