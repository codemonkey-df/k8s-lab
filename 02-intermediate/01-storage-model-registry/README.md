# I01 — Storage: rejestr modeli i offline feature store

**Czas:** ~45 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/01-storage-model-registry/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Zbudować dwa magazyny, na których oprze się pipeline FTI:

| Magazyn | Obiekt | Tryb | Rola w FTI |
|---|---|---|---|
| `model-store` | statyczny PV + PVC, `hostPath` na `/mnt/shared` | RWX, `Retain` | rejestr modeli (T → I) |
| `features` | dynamiczny PVC ze StorageClass `standard` | RWO, `Delete` | offline feature store (F → T) |

W produkcji: rejestr = S3/GCS/MinIO lub MLflow, cechy = data lake / Feast. Mechanika K8s (PV/PVC/StorageClass, tryby dostępu) jest ta sama.

## Kroki

### 1. PV i PVC

▶️ **Wklej do terminala:**
```sh
kubectl get storageclass          # standard (default), rancher.io/local-path, WaitForFirstConsumer
kubectl apply -f 02-intermediate/01-storage-model-registry/storage.yaml
kubectl get pv,pvc
```
`model-store` jest `Bound` od razu, `features` — `Pending`. Dlaczego? (`kubectl describe pvc features`)

### 2. Zapis modelu do rejestru

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/01-storage-model-registry/writer-pod.yaml
kubectl logs -f train-to-registry
ls -la $LAB_DATA/models/v0        # model widoczny na HOŚCIE
kubectl delete pod train-to-registry
ls $LAB_DATA/models/v0            # nadal jest
```

### ✍️ 3. Zadanie: Pod z cache modelu

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/01-storage-model-registry/writer-pod.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/i01/cache-pod.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/i01 && cp 02-intermediate/01-storage-model-registry/writer-pod.yaml $WORK/i01/cache-pod.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I01` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `02-intermediate/01-storage-model-registry/writer-pod.yaml` napisz `$WORK/i01/cache-pod.yaml` — Pod `cache-demo`, który montuje `model-store` **tylko do odczytu** w `/models` i `emptyDir` (limit 200Mi) w `/cache`, kopiuje model do cache i śpi. Sprawdź, że zapis do `/models` się nie udaje (`kubectl exec cache-demo -- touch /models/x`), a potem `./setup/check.sh I01`.

<details><summary>Rozwiązanie</summary>

`02-intermediate/01-storage-model-registry/solution/cache-pod.yaml`
</details>

### 4. Reclaim policy

▶️ **Wklej do terminala:**
```sh
kubectl get pv model-store -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'   # Retain
kubectl get pv -o custom-columns=NAME:.metadata.name,CLAIM:.spec.claimRef.name,POLICY:.spec.persistentVolumeReclaimPolicy
```
Co się stanie z danymi po `kubectl delete pvc features`, a co po `kubectl delete pvc model-store`? (Na razie nie kasuj — używamy dalej.)

## Pytania
1. RWO vs RWX vs ROX vs RWOP — który tryb dla rejestru modeli, który dla bazy danych?
2. Dlaczego `WaitForFirstConsumer` jest ważne przy storage lokalnym (i przy węzłach GPU w różnych strefach)?
3. `emptyDir.medium: Memory` dla dużych wag modelu — jaki jest haczyk?

## Sprzątanie

**Usuń** — Pod z zadania — tylko pokaz montowania read-only:

▶️ **Wklej do terminala:**
```sh
kubectl delete pod cache-demo --ignore-not-found
```

**Zostaw:**
- PV/PVC `model-store` (rejestr modeli) → każdy kolejny lab trenuje/serwuje z niego. **Nie usuwaj PVC**: PV ma `Retain`, przejdzie w `Released` i nie zwiąże się ponownie bez usunięcia PV
- PVC `features` → I02 (pierwszy konsument go zwiąże)
