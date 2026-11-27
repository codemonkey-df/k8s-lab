# I08 — Kustomize: te same manifesty, środowiska dev i prod

**Czas:** ~45 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/08-kustomize-envs/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Jedna baza manifestów inference + nakładki per środowisko (namespace, repliki, konfiguracja, routing). Zobaczyć, jak `configMapGenerator` rozwiązuje problem „zmiana ConfigMap nie restartuje Podów” z B07.

## Kroki

### 1. Podgląd i wdrożenie dev

▶️ **Wklej do terminala:**
```sh
kubectl kustomize 02-intermediate/08-kustomize-envs/overlays/dev | less
kubectl apply -k 02-intermediate/08-kustomize-envs/overlays/dev
kubectl -n ml-dev get deploy,svc,cm
```

### ✍️ 2. Zmiana konfiguracji dev

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (plik laba — tu wyjątkowo zmieniasz przykład (to Twoje środowisko dev)): `02-intermediate/08-kustomize-envs/overlays/dev/kustomization.yaml`

**Co zrobić:** Zmień w `02-intermediate/08-kustomize-envs/overlays/dev` `LOG_LEVEL=WARNING`, `kubectl apply -k 02-intermediate/08-kustomize-envs/overlays/dev` → nowa nazwa ConfigMap (`inference-config-<hash>`) → automatyczny rollout.

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl -n ml-dev get cm ; kubectl -n ml-dev rollout history deploy/inference
```

### ✍️ 3. Zadanie — overlay `prod`

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): katalog `02-intermediate/08-kustomize-envs/overlays/dev/`
> - 📝 **Twój plik** (nowy — tworzysz (katalog w labie, obok `dev`)): `02-intermediate/08-kustomize-envs/overlays/prod/`
> - ▶️ **Start:** `cp -r 02-intermediate/08-kustomize-envs/overlays/dev 02-intermediate/08-kustomize-envs/overlays/prod`
> - ✅ **Sprawdzenie:** `./setup/check.sh I08` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `02-intermediate/08-kustomize-envs/overlays/dev` napisz nowy katalog `02-intermediate/08-kustomize-envs/overlays/prod` (namespace `ml-prod`):
- `replicas: 3` (patch),
- `LOG_LEVEL=WARNING`, `MODEL_VERSION=v1`,
- większe zasoby (`requests.cpu: 250m`, `memory: 512Mi`, limit `1Gi`),
- `HTTPRoute` na `ml-gateway` (namespace `infra`) dla hosta `prod.127-0-0-1.nip.io`,
- `images.newTag` — tag obrazu ustawiony w overlayu (np. `0.1`), a nie w bazie.

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl create ns ml-prod --save-config   # diff nie działa dla nieistniejącego namespace (NotFound)
kubectl diff -k 02-intermediate/08-kustomize-envs/overlays/prod     # przed apply: co się zmieni
kubectl apply -k 02-intermediate/08-kustomize-envs/overlays/prod
curl -s http://prod.127-0-0-1.nip.io/version
./setup/check.sh I08
```

<details><summary>Rozwiązanie</summary>

`02-intermediate/08-kustomize-envs/solution/prod/`
</details>

## Pytania
1. Kustomize vs Helm — kiedy co? (patchowanie cudzych manifestów vs parametryzowana paczka z wersjonowaniem)
2. Jak ArgoCD/Flux używają overlayów w GitOps (jeden katalog = jedna aplikacja/środowisko)?
3. Dlaczego `includeSelectors: false` przy wspólnych etykietach?

## Sprzątanie

**Usuń** — osobne środowiska tylko na ten lab (`ml-dev`, `ml-prod`) — 4 dodatkowe Pody inference:

▶️ **Wklej do terminala:**
```sh
kubectl delete -k 02-intermediate/08-kustomize-envs/overlays/dev
kubectl delete ns ml-dev ml-prod --ignore-not-found   # ml-prod z Twojego overlayu prod (jeśli robiłeś zadanie)
```

**Zostaw:**
- pliki overlayów (`02-intermediate/08-kustomize-envs/overlays/prod`) — przydadzą się jako wzór; I09 tworzy `ml-prod` od nowa
