# I06 — metrics-server i HPA: autoskalowanie inference

**Czas:** ~40 min  
**Wymaga:** Deployment `inference` + Service.  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/06-hpa-autoscaling/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Skalować serwer modelu automatycznie wraz z ruchem i zrozumieć, dlaczego CPU to dobra metryka dla małego modelu, a zła dla LLM.

## Kroki

### 1. metrics-server (w kind trzeba wyłączyć weryfikację TLS kubeleta)

▶️ **Wklej do terminala:**
```sh
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server
kubectl top nodes ; kubectl top pods
```

### 2. HPA + ruch (dwa terminale)

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/06-hpa-autoscaling/hpa.yaml
kubectl get hpa inference -w                 # terminal 1
kubectl apply -f 02-intermediate/06-hpa-autoscaling/load.yaml                   # terminal 2
kubectl top pods -l app=inference
```
Po 1–2 min repliki rosną (max 6). Zatrzymaj ruch: `kubectl delete -f 02-intermediate/06-hpa-autoscaling/load.yaml` — po 1–3 min spadek do 2 (okno stabilizacji 60 s + opóźnienie metryk).

### 3. Diagnostyka HPA

▶️ **Wklej do terminala:**
```sh
kubectl describe hpa inference      # Events: SuccessfulRescale, Conditions: AbleToScale/ScalingActive/ScalingLimited
```

### ✍️ 4. Zadanie: HPA bez requests i własne behavior

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (masz go z I03 — zmieniasz): `$WORK/inference.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I06`

**Co zrobić:** Usuń `resources.requests.cpu` w `$WORK/inference.yaml`, `kubectl apply -f` i obserwuj HPA (`<unknown>/60%`, `FailedGetResourceMetric` w `describe hpa`). Przywróć w pliku, zaaplikuj i sprawdź: `./setup/check.sh I06`.

#### ✍️ Własne `behavior` HPA

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/06-hpa-autoscaling/hpa.yaml`
> - 📝 **Twój plik** (kopia przykładu — zmieniasz): `$WORK/i06/hpa.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/i06 && cp 02-intermediate/06-hpa-autoscaling/hpa.yaml $WORK/i06/`
> - ✅ **Sprawdzenie:** `./setup/check.sh I06` · rozwiązanie zwinięte na końcu

**Co zrobić:** Skopiuj `02-intermediate/06-hpa-autoscaling/hpa.yaml` do `$WORK/i06/` i zmień `behavior.scaleDown` tak, by schodził o max 1 Pod na 30 s (`policies` z `type: Pods`). Obserwuj tempo spadku po `kubectl delete -f 02-intermediate/06-hpa-autoscaling/load.yaml`. `./setup/check.sh I06` sprawdza też tę politykę.

<details><summary>Rozwiązanie</summary>

`02-intermediate/06-hpa-autoscaling/solution/hpa.yaml`
</details>

## Pytania
1. Dlaczego HPA wymaga `requests.cpu`?
2. Dla LLM na GPU CPU jest ~stałe — po czym skalować? (długość kolejki / liczba żądań w locie / KV-cache / `vllm:num_requests_waiting` → HPA na custom metrics albo KEDA)
3. HPA + `kubectl scale` ręcznie — kto wygra?
4. Scale-to-zero dla rzadko używanych modeli — czym? (KEDA, Knative/KServe serverless)

## Sprzątanie

**Usuń** — generator obciążenia — zjada CPU i trzyma HPA na maksimum replik:

▶️ **Wklej do terminala:**
```sh
kubectl delete -f 02-intermediate/06-hpa-autoscaling/load.yaml --ignore-not-found
```

**Zostaw:**
- metrics-server → `kubectl top`, HPA, A08
- HPA `inference` (minReplicas 2 = tyle, ile zakładają kolejne laby). Usunięcie (`kubectl delete hpa inference`) też jest OK — wtedy liczbę replik ustala `$WORK/inference.yaml` (2)
