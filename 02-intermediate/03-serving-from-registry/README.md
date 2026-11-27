# I03 — Serwowanie modelu z rejestru (initContainer)

**Czas:** ~40 min  
**Wymaga:** model `v1` w rejestrze (I02), Service `inference` (B04).  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/03-serving-from-registry/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Domknąć pętlę FTI: inference serwuje model **wytrenowany w klastrze**, a nie wypalony w obrazie. Nowa wersja modelu = zmiana jednej zmiennej i rollout.

## Kroki

### 1. Zastąp Deployment z B06/B07 — **usuń i utwórz od nowa**

▶️ **Wklej do terminala:**
```sh
kubectl delete deploy inference
cp 02-intermediate/03-serving-from-registry/deployment.yaml $WORK/inference.yaml     # TWÓJ manifest inference — rozbudowujesz go do I07
kubectl apply -f $WORK/inference.yaml
kubectl get pods -l app=inference -w        # Init:0/1 -> PodInitializing -> Running
kubectl logs deploy/inference -c fetch-model
curl -s localhost:30080/version | python3 -m json.tool    # model_version: v1, accuracy z treningu
```
Dlaczego `delete`? Zmienne ustawione w B06 przez `kubectl set env` (np. `MODEL_VERSION=baked-1`)
**przetrwałyby** `kubectl apply`. Apply usuwa tylko pola, które sam wcześniej dodał (adnotacja
`last-applied-configuration`), a `/version` pokazałby starą wersję. Sprawdzone przy teście laba.
Wniosek: nie mieszaj `apply` z imperatywnymi `set`/`edit` na tym samym obiekcie (albo przejdź na `kubectl apply --server-side`).

### 2. Brakujący model (celowo imperatywnie — szybkie zepsucie, potem `undo`)

▶️ **Wklej do terminala:**
```sh
kubectl set env deploy/inference -c fetch-model MODEL_VERSION=v9
kubectl get pods -l app=inference              # Init:Error / Init:CrashLoopBackOff, stare Pody dalej serwują
kubectl logs <nowy-pod> -c fetch-model         # "brak modelu /registry/v9"
kubectl rollout undo deploy/inference
```

### ✍️ 3. Zadanie: trening v2 i rollout

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/02-jobs-fti-pipeline/train-job.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/i03/train-v2.yaml`
> - 📝 **Twój plik** (masz go z kroku 1 — zmieniasz): `$WORK/inference.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/i03 && cp 02-intermediate/02-jobs-fti-pipeline/train-job.yaml $WORK/i03/train-v2.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I03` · rozwiązanie zwinięte na końcu

**Co zrobić:** Wytrenuj `v2` i wypuść go rolloutem — wszystko z plików:
- na bazie `02-intermediate/02-jobs-fti-pipeline/train-job.yaml` napisz `$WORK/i03/train-v2.yaml` (Job `train-v2`, `N_ESTIMATORS=200`, bez `MAX_DEPTH`, katalog `/models/v2`),
- w `$WORK/inference.yaml` zmień `MODEL_VERSION` initContainera na `v2` i dodaj adnotację `kubernetes.io/change-cause` z wersją i accuracy,

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl apply -f $WORK/i03/train-v2.yaml && kubectl wait --for=condition=Complete job/train-v2 --timeout=3m
kubectl diff -f $WORK/inference.yaml
kubectl apply -f $WORK/inference.yaml && kubectl rollout status deploy/inference
curl -s localhost:30080/version | python3 -m json.tool     # v1 vs v2: accuracy
./setup/check.sh I03
```

<details><summary>Rozwiązanie</summary>

`02-intermediate/03-serving-from-registry/solution/train-v2.yaml`
`02-intermediate/03-serving-from-registry/solution/inference.yaml`
</details>

### 4. Historia „wersji modelu” = historia Deploymentu

▶️ **Wklej do terminala:**
```sh
kubectl rollout history deploy/inference
```

## Pytania
1. Dlaczego kopia do `emptyDir` zamiast montować rejestr bezpośrednio w kontenerze serwera? (Hint: S3 nie jest systemem plików; atomowość; cache lokalny)
2. Jak to robi KServe (`storageUri`) i co daje „model as OCI image” (modelcar / ImageVolume)?
3. Init container vs sidecar (`restartPolicy: Always` w `initContainers`) — kiedy który?

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- Deployment `inference` (v2) z `$WORK/inference.yaml` → rozbudowujesz go w I04, I06, I07; używają go I05–A08
- modele `v1`, `v2` w rejestrze → A05 (canary v1/v2)
