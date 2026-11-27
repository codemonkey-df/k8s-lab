#!/usr/bin/env bash
# Trening vN z bramką jakości. Exit 0 = model przeszedł bramkę i jest w rejestrze /models/vN.
#   ./train.sh v4                      # domyślne hiperparametry (zwykle przechodzi)
#   N_ESTIMATORS=1 MAX_DEPTH=1 MIN_ACCURACY=0.99 ./train.sh v5    # model odrzucony
set -euo pipefail
V=${1:?wersja, np. v4}
cd "$(dirname "$0")"
# świeże cechy przed treningiem
kubectl -n ml create job "features-for-$V" --from=cronjob/feature-pipeline >/dev/null
kubectl -n ml wait --for=condition=Complete "job/features-for-$V" --timeout=180s >/dev/null
kubectl -n ml delete job "train-$V" --ignore-not-found >/dev/null
sed -e "s/__VERSION__/$V/g" -e "s/__N_ESTIMATORS__/${N_ESTIMATORS:-100}/" \
    -e "s/__MAX_DEPTH__/${MAX_DEPTH:-}/" -e "s/__MIN_ACCURACY__/${MIN_ACCURACY:-0.85}/" train-job.yaml | kubectl apply -f - >/dev/null
# czekamy na Complete albo Failed (co pierwsze)
until S=$(kubectl -n ml get job "train-$V" -o jsonpath='{.status.conditions[?(@.status=="True")].type}'); [[ "$S" =~ Complete|Failed ]]; do sleep 3; done
kubectl -n ml logs "job/train-$V" | tail -2
if [[ "$S" =~ Complete ]]; then echo "OK: $V w rejestrze"; else echo "ODRZUCONY: $V (stable bez zmian)"; exit 1; fi
