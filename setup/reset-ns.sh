#!/usr/bin/env bash
# Czyści namespace ml (szybszy "restart" laba niż odtwarzanie klastra).
set -euo pipefail
source "$(dirname "$0")/env.sh"
kubectl delete ns ml --ignore-not-found --wait
kubectl create ns ml
kubectl config set-context --current --namespace=ml
