# I02 — Job i CronJob: pipeline Feature → Training

**Czas:** ~60 min  
**Wymaga:** PVC `features` i `model-store` z I01.  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/02-jobs-fti-pipeline/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Złożyć część **F** i **T** pipeline'u: cykliczne liczenie cech (CronJob), trening z bramką jakości (Job), równoległy sweep hiperparametrów (Indexed Job).

```
CronJob feature-pipeline ──► PVC features/latest.csv ──► Job train-v1 ──► PVC model-store/v1/
                                                    └──► Indexed Job hpo-sweep-1 ──► model-store/sweep-1/trial-{0..4}
```

## Kroki

### 1. Feature pipeline

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/02-jobs-fti-pipeline/feature-cronjob.yaml
kubectl create job features-manual --from=cronjob/feature-pipeline   # nie czekaj 5 min
kubectl logs -f job/features-manual
kubectl get pvc features          # teraz Bound (pierwszy konsument)
```

### 2. Trening

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/02-jobs-fti-pipeline/train-job.yaml
kubectl get job train-v1 -w
kubectl logs job/train-v1
cat $LAB_DATA/models/v1/metrics.json
```
Zauważ: Pod treningu wylądował na **tym samym węźle**, co Pod cech (`-o wide`). Dlaczego? (PV `local-path` ma `nodeAffinity`.)

### 3. Sweep hiperparametrów

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/02-jobs-fti-pipeline/hpo-indexed-job.yaml
kubectl get pods -l app=hpo -L batch.kubernetes.io/job-completion-index -w
kubectl get job hpo-sweep-1     # COMPLETIONS 5/5
./02-intermediate/02-jobs-fti-pipeline/solution/pick-best.sh
```

### ✍️ 4. Zadanie — bramka jakości

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/02-jobs-fti-pipeline/train-job.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/i02/train-bad.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/i02 && cp 02-intermediate/02-jobs-fti-pipeline/train-job.yaml $WORK/i02/train-bad.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I02` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `02-intermediate/02-jobs-fti-pipeline/train-job.yaml` napisz `$WORK/i02/train-bad.yaml` — Job `train-bad` z `N_ESTIMATORS=1`, `MAX_DEPTH=1`, `MIN_ACCURACY=0.99`. Ile razy Pod się powtórzy przy `backoffLimit: 3`? Dodaj `podFailurePolicy`, żeby exit code `1` (odrzucony model) od razu kończył Job jako `Failed` bez ponawiania (`kubectl explain job.spec.podFailurePolicy`). Sprawdź: `./setup/check.sh I02`.

<details><summary>Rozwiązanie</summary>

`02-intermediate/02-jobs-fti-pipeline/solution/train-gate-fail.yaml`
</details>

### 5. CronJob w praktyce

▶️ **Wklej do terminala:**
```sh
kubectl get cronjob,jobs -l part-of=fti
kubectl patch cronjob feature-pipeline -p '{"spec":{"suspend":true}}'   # wstrzymanie
```

## Pytania
1. `restartPolicy: OnFailure` vs `Never` w Jobie — co widać w `kubectl get pods` w obu przypadkach?
2. `concurrencyPolicy: Forbid / Allow / Replace` — co wybrać dla treningu, który może trwać dłużej niż interwał?
3. Jak w realnym MLOps uruchamia się trening „po pojawieniu się nowych danych” zamiast z crona? (Argo Workflows, Kubeflow Pipelines, Airflow z KubernetesPodOperator — każde tworzy pod spodem Pody/Joby.)
4. Wzorzec kolejki (producent wrzuca zadania do Redisa, N workerów je zdejmuje) — kiedy lepszy od Indexed Job? (batch inference po milionie rekordów)

## Sprzątanie

**Usuń** — Joby jednorazowe z kroków i zadania (modele zostają w rejestrze); **wznowienie CronJoba** z kroku 5 — wstrzymany = nieświeże cechy, a w A08 od razu odpali alert `FeaturesStale`:

▶️ **Wklej do terminala:**
```sh
kubectl delete job train-bad features-manual hpo-sweep-1 --ignore-not-found
kubectl patch cronjob feature-pipeline -p '{"spec":{"suspend":false}}'
```

**Zostaw:**
- CronJob `feature-pipeline` → I04 (podłączenie do Redisa), A06–A08
- Job `train-v1` i modele `v1`, `sweep-*` w rejestrze → I03 serwuje `v1` (Job sam zniknie po dobie: `ttlSecondsAfterFinished`)
