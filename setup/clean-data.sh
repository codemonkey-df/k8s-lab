#!/usr/bin/env bash
# Czyści $LAB_DATA (modele, cechy). Pliki zapisane przez Pody mają właściciela UID 10001,
# więc zwykłe `rm` z hosta nie zadziała — usuwamy je z kontenera (root w kontenerze, bez sudo).
set -euo pipefail
source "$(dirname "$0")/env.sh"
[ -d "$LAB_DATA" ] || { echo "Brak $LAB_DATA"; exit 0; }
docker run --rm -v "$LAB_DATA":/data busybox:1.36 sh -c 'rm -rf /data/* /data/.[!.]* 2>/dev/null; true'
rmdir "$LAB_DATA" 2>/dev/null || true
echo "Wyczyszczono $LAB_DATA"
