# I04 — StatefulSet: online feature store (Redis)

**Czas:** ~40 min  
**Wymaga:** CronJob `feature-pipeline` (I02), Deployment `inference` (I03).  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/04-statefulset-feature-store/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Dodać **online** feature store: feature pipeline pisze najnowsze cechy encji do Redisa, a inference pobiera je po `entity_id` (`GET /predict/entity/{id}`). To typowy podział w architekturze FTI: offline store do treningu, online store do inferencji o niskim opóźnieniu.

```
feature-pipeline ──► features PVC (offline) ──► training
          └────────► Redis feature-store-0 (online) ──► inference /predict/entity/42
```

## Kroki

### 1. Redis jako StatefulSet

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/04-statefulset-feature-store/feature-store.yaml
kubectl get sts,pods,pvc -l app=feature-store     # Pod feature-store-0, PVC data-feature-store-0
kubectl run dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup feature-store
```

### ✍️ 2. Zadanie A: pipeline cech → Redis

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/02-jobs-fti-pipeline/feature-cronjob.yaml`
> - 📝 **Twój plik** (kopia przykładu — dopisujesz env): `$WORK/feature-cronjob.yaml`
> - ▶️ **Start:** `cp 02-intermediate/02-jobs-fti-pipeline/feature-cronjob.yaml $WORK/`

**Co zrobić:** Podłącz feature pipeline do online store — skopiuj CronJob (`cp 02-intermediate/02-jobs-fti-pipeline/feature-cronjob.yaml $WORK/`), dodaj w `$WORK/feature-cronjob.yaml` env `REDIS_HOST=feature-store` i `kubectl apply -f`. Odpal ręcznie (`kubectl create job --from=cronjob/feature-pipeline f-online`) i sprawdź:

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl exec feature-store-0 -- redis-cli get features:42
kubectl exec feature-store-0 -- redis-cli get features:updated_at
```

### ✍️ 3. Zadanie B: inference czyta z Redisa

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (masz go z I03 — zmieniasz): `$WORK/inference.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I04` · rozwiązanie zwinięte na końcu

**Co zrobić:** Dodaj `REDIS_HOST=feature-store` do kontenera `server` w `$WORK/inference.yaml` (z I03), `kubectl apply -f $WORK/inference.yaml` i:

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl rollout status deploy/inference && sleep 6   # stare Pody jeszcze ~5 s odpowiadają (preStop)
curl -s localhost:30080/predict/entity/42
curl -s localhost:30080/predict/entity/9999       # 404 — brak encji
./setup/check.sh I04
```

<details><summary>Rozwiązanie</summary>

`02-intermediate/04-statefulset-feature-store/solution/feature-cronjob.yaml`
`02-intermediate/04-statefulset-feature-store/solution/inference.yaml`
</details>

### 4. Trwałość i tożsamość

▶️ **Wklej do terminala:**
```sh
kubectl delete pod feature-store-0
kubectl get pod feature-store-0 -w            # wraca z TĄ SAMĄ nazwą i TYM SAMYM PVC
kubectl exec feature-store-0 -- redis-cli dbsize
```

### 5. EXTRA: skalowanie StatefulSetu

`kubectl scale sts feature-store --replicas=3` — kolejność tworzenia (0→1→2), potem z powrotem do 1. Co się stało z PVC `data-feature-store-1/2`?

## Pytania
1. Czym StatefulSet różni się od Deploymentu z PVC? (tożsamość, kolejność, PVC per replika)
2. Czy 3 repliki Redisa w StatefulSecie to klaster Redisa z replikacją? (Nie — to robi operator/Helm chart.)
3. Dlaczego online store nie powinien być sprawdzany w liveness probe inference?

## Sprzątanie

**Usuń** — tylko jeśli robiłeś EXTRA: StatefulSet przy skalowaniu w dół **nie kasuje** PVC replik 1 i 2 — leżą i zajmują dysk:

▶️ **Wklej do terminala:**
```sh
kubectl delete pvc data-feature-store-1 data-feature-store-2 --ignore-not-found
```

**Zostaw:**
- StatefulSet `feature-store` (Redis) + PVC `data-feature-store-0` → A06 (polityki), A07 (utwardzenie)
- CronJob z `REDIS_HOST` i inference z `REDIS_HOST` → `/predict/entity/{id}` w kolejnych labach
