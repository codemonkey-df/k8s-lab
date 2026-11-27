#!/usr/bin/env bash
# Zmiana modelu LLM z bramką ewaluacji i automatycznym powrotem:
#   ./llm-release.sh qwen2.5:1.5b
set -uo pipefail
NEW=${1:?model, np. qwen2.5:1.5b}
cd "$(dirname "$0")"
PREV=$(kubectl -n llm get cm llm-config -o jsonpath='{.data.MODEL}')
deploy() {   # $1 = model: pull do PVC + alias llm, restart serwera
  kubectl -n llm patch cm llm-config --type=merge -p "{\"data\":{\"MODEL\":\"$1\"}}" >/dev/null
  kubectl -n llm delete job llm-pull --ignore-not-found >/dev/null
  kubectl apply -f llm-pull-job.yaml >/dev/null 2>&1
  kubectl -n llm wait --for=condition=Complete job/llm-pull --timeout=1800s >/dev/null || { kubectl -n llm logs job/llm-pull | tail -3; return 1; }
  kubectl -n llm rollout restart deploy/ollama >/dev/null 2>&1 && kubectl -n llm rollout status deploy/ollama --timeout=300s >/dev/null
}
evaluate() {
  kubectl -n llm delete job llm-eval --ignore-not-found >/dev/null
  kubectl apply -f ../llm-eval-job.yaml >/dev/null 2>&1
  until S=$(kubectl -n llm get job llm-eval -o jsonpath='{.status.conditions[?(@.status=="True")].type}'); [[ "$S" =~ Complete|Failed ]]; do sleep 5; done
  kubectl -n llm logs job/llm-eval | tail -1
  [[ "$S" =~ Complete ]]
}
echo "== $PREV -> $NEW"
deploy "$NEW" || { echo "pobranie $NEW nieudane -> zostaje $PREV"; deploy "$PREV"; exit 1; }
if evaluate; then echo "OK: $NEW w produkcji"; exit 0; fi
echo "BRAMKA: $NEW odrzucony -> powrót do $PREV"
deploy "$PREV" && evaluate && echo "przywrócono $PREV"
exit 1
