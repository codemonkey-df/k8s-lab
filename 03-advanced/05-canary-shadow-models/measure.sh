#!/usr/bin/env bash
# Rozkład odpowiedzi między wersjami modelu (100 żądań)
for i in $(seq 1 100); do
  curl -s -XPOST http://wine.127-0-0-1.nip.io/predict -H 'content-type: application/json' "$@" \
    -d '{"instances":[[13.2,1.8,2.1,16,100,2.4,2.6,0.3,1.9,5.6,1.0,3.2,1100]]}' \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["model_version"])'
done | sort | uniq -c
