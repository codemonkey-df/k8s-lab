# B02 — Obraz aplikacji FTI i `kind load`

**Czas:** ~20 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/02-image-kind-load/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Zbudować obraz `fti-lab:0.1` (feature pipeline + trening + inference w jednym obrazie) i dostarczyć go do węzłów kind bez rejestru.

## Dlaczego to ważne dla MLOps
Model i jego środowisko (wersje `scikit-learn`, `torch`, CUDA) muszą być identyczne w treningu i w serwowaniu. Jeden obraz z przypiętymi wersjami to najprostszy sposób, żeby to zagwarantować.

## Aplikacja (`app/`)
| Moduł | Krok FTI | Uruchomienie |
|---|---|---|
| `fti.features` | **F**eature pipeline → CSV (offline) + Redis (online) | `python -m fti.features` |
| `fti.train` | **T**raining → `model.joblib` + `metrics.json` | `python -m fti.train` |
| `fti.serve` | **I**nference → HTTP `:8080` | domyślny `CMD` (uvicorn) |

Obraz ma „wypalony” model `baked-0`, więc inference działa od razu.

## Kroki

### 1. Build + load

▶️ **Wklej do terminala:**
```sh
./app/build.sh 0.1
```

### 2. Gdzie jest obraz? Na węzłach, w containerd (nie w Dockerze hosta)

▶️ **Wklej do terminala:**
```sh
docker exec mlops-worker crictl images | grep fti-lab
```

### 3. Szybki test w klastrze

▶️ **Wklej do terminala:**
```sh
kubectl run smoke --image=fti-lab:0.1 --restart=Never --rm -it -- python -m fti.train --out /tmp/m --version smoke
```

### 4. Pułapka: tag :latest

tag `:latest` → domyślnie `imagePullPolicy: Always` → kind próbuje ciągnąć z Docker Hub → `ErrImagePull`.

▶️ **Wklej do terminala:**
```sh
docker tag fti-lab:0.1 fti-lab:latest && kind load docker-image fti-lab:latest --name mlops
kubectl run bad --image=fti-lab:latest
kubectl get pod bad -w        # ErrImagePull / ImagePullBackOff
kubectl delete pod bad
```

## Pytania
1. Dlaczego Dockerfile tworzy użytkownika o UID `10001`, a nie korzysta z roota?
2. Kiedy `imagePullPolicy` jest `Always`, a kiedy `IfNotPresent` przy braku jawnego ustawienia?
3. Jak w produkcji zastąpisz `kind load`? (rejestr, `imagePullSecrets`, pre-pull dużych obrazów LLM)

## Sprzątanie

**Usuń** — Pod `bad` z pułapki `:latest` (jeśli nie usunąłeś w kroku 4) — tylko demo:

▶️ **Wklej do terminala:**
```sh
kubectl delete pod bad --ignore-not-found
```

**Zostaw:**
- obraz `fti-lab:0.1` w węzłach kind → każdy kolejny lab (bez niego `ErrImageNeverPull`)
- `fti-lab:latest` w węzłach nie przeszkadza (od A07 i tak blokuje go polityka VAP)
