# B03 — Pod: pierwszy serwer inference

**Czas:** ~40 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/03-pod/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Uruchomić serwer modelu jako Pod, odpytać go, przeczytać logi i zdarzenia, poćwiczyć etykiety i selektory.

## Kroki

### 1. Start i obserwacja

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 01-basic/03-pod/pod.yaml
kubectl get pod inference -o wide -w
kubectl describe pod inference     # sekcja Events: Scheduled -> Pulled -> Created -> Started
kubectl logs inference
```

### 2. Odpytanie modelu przez `port-forward`

▶️ **Wklej do terminala:**
```sh
kubectl port-forward pod/inference 8080:8080 &
curl -s localhost:8080/version | python3 -m json.tool
curl -s -XPOST localhost:8080/predict -H 'content-type: application/json' \
  -d '{"instances":[[13.2,1.8,2.1,16,100,2.4,2.6,0.3,1.9,5.6,1.0,3.2,1100]]}'
curl -s localhost:8080/metrics | grep fti_
kill %1
```

### 3. Do środka Poda

▶️ **Wklej do terminala:**
```sh
kubectl exec -it inference -- sh
#  id ; ls /opt/model ; cat /opt/model/metrics.json ; env | grep MODEL
```

### 4. Etykiety i selektory

▶️ **Wklej do terminala:**
```sh
kubectl get pods --show-labels
kubectl label pod inference stage=inference model=baked-0
kubectl get pods -l 'app=inference,stage in (inference,canary)' -L model
kubectl label pod inference model=baked-1 --overwrite
kubectl label pod inference model-        # usunięcie
```

## ✍️ Zadanie

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `01-basic/03-pod/pod.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/b03/train-once.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/b03 && cp 01-basic/03-pod/pod.yaml $WORK/b03/train-once.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh B03` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `01-basic/03-pod/pod.yaml` napisz `$WORK/b03/train-once.yaml`: Pod `train-once` z tego samego obrazu, który **jednorazowo** trenuje model
(`python -m fti.train --out /tmp/model --version pod-run`) i kończy się statusem `Completed` (nie restartuje się).
Odczytaj accuracy z logów. Etykiety: `app: training`, `part-of: fti`.

Podpowiedź: `restartPolicy`, `command`/`args` (`kubectl explain pod.spec.restartPolicy`).

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl apply -f $WORK/b03/train-once.yaml
kubectl get pod train-once -w          # Running -> Completed, RESTARTS 0
kubectl logs train-once
./setup/check.sh B03
```

<details><summary>Rozwiązanie</summary>

`01-basic/03-pod/solution/train-once.yaml`
</details>

## Pytania
1. Co się stanie z wytrenowanym modelem po zakończeniu Poda `train-once`? (→ lab I01)
2. Dlaczego „gołego” Poda nie używa się w produkcji do serwowania?
3. `kubectl delete pod inference` — kto go odtworzy?

## Sprzątanie

**Usuń** — Pod treningowy z zadania — skończył pracę, nic go nie używa:

▶️ **Wklej do terminala:**
```sh
kubectl delete pod train-once --ignore-not-found
```

**Zostaw:**
- Pod `inference` → B04 (Service potrzebuje Poda z etykietą `app: inference`, żeby mieć endpoint)
