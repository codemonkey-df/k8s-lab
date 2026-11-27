#!/usr/bin/env bash
# Wybór najlepszego triala ze sweepu (czyta metrics.json z rejestru na hoście)
set -euo pipefail
source "$(dirname "$0")/../../../setup/env.sh"
for f in "$LAB_DATA"/models/sweep-1/trial-*/metrics.json; do
  python3 -c "import json,sys; m=json.load(open('$f')); print(m['accuracy'], '$f', m['params'])"
done | sort -rn | head -1
