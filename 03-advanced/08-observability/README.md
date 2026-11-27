# A08 — Obserwowalność: Prometheus, Grafana, alerty dla FTI

**Czas:** ~75 min  
**Wymaga:** klaster z setup/ (bind-addressy pod monitoring są już w `kind-mlops.yaml`).  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/08-observability/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Monitorować nie tylko „czy Pod żyje”, ale całe FTI: latencję i błędy modelu (I), świeżość cech (F), porażki treningu (T).

## Kroki

### 1. kube-prometheus-stack (~2–3 GB RAM)

▶️ **Wklej do terminala:**
```sh
helm upgrade --install --wait --timeout 15m -n monitoring --create-namespace \
  --repo https://prometheus-community.github.io/helm-charts \
  kube-prometheus-stack kube-prometheus-stack --version 94.1.0 -f 03-advanced/08-observability/values.yaml
kubectl -n monitoring get pods
kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 &
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
```

### 2. Metryki modelu

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/08-observability/podmonitor.yaml
# Prometheus -> Status -> Targets: podMonitor/ml/fti-inference (UP)
```
Jeśli masz polityki z A06 — `monitoring` jest już wpuszczony do `:8080`.
Zapytania (Prometheus/Grafana Explore):

▶️ **Wklej w Prometheus → Graph / Grafana → Explore:**
```promql
sum by (model_version) (rate(fti_predictions_total[5m]))
histogram_quantile(0.95, sum by (le, app) (rate(fti_predict_latency_seconds_bucket[5m])))
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="ml", container="server"}[5m]))
kube_job_status_succeeded{namespace="ml"}
time() - kube_cronjob_status_last_successful_time{namespace="ml"}
```

### 3. Alerty

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/08-observability/prometheus-rules.yaml
# Prometheus -> Alerts: fti-inference, fti-pipeline
```
Wywołaj je (każdy sprawdzony; `for:` + interwał ewaluacji = 1–6 min do `firing`):

▶️ **Wklej do terminala:**
```sh
# InferenceDown (~2 min)
kubectl scale deploy inference --replicas=0
# FeaturesStale (>15 min od ostatniego udanego Joba cech)
kubectl patch cronjob feature-pipeline -p '{"spec":{"suspend":true}}'
# TrainingJobFailed — model zawsze odrzucany przez bramkę
kubectl apply -f 03-advanced/08-observability/train-bad.yaml
# InferenceHighLatencyP95 + InferenceErrorRate — wolny model i ruch z błędami (encja spoza store) przez ~6 min
kubectl set env deploy/inference -c server PREDICT_DELAY_MS=400
end=$(( $(date +%s) + 420 )); while [ $(date +%s) -lt $end ]; do
  curl -s -o /dev/null -XPOST http://ml.127-0-0-1.nip.io/predict -H 'content-type: application/json' \
    -d '{"instances":[[13.2,1.8,2.1,16,100,2.4,2.6,0.3,1.9,5.6,1.0,3.2,1100]]}'
  curl -s -o /dev/null http://ml.127-0-0-1.nip.io/predict/entity/99999; done
```
Przywrócenie:

▶️ **Wklej do terminala:**
```sh
kubectl scale deploy inference --replicas=2 ; kubectl set env deploy/inference -c server PREDICT_DELAY_MS-
kubectl patch cronjob feature-pipeline -p '{"spec":{"suspend":false}}' ; kubectl delete job train-bad
```
Pułapka (była w tej regule): `sum(up{...}) == 0` **nie** odpala przy 0 replik — brak targetów to brak serii, a nie zero. Stąd `or vector(0)`.

### ✍️ 4. Zadanie: dashboard FTI

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): zapytania PromQL z kroku 2
> - 📝 **Twój plik** (nowy — tworzysz — eksport z Grafany (Share → Export), nie piszesz ręcznie): `$WORK/a08/dashboard-fti.json`
> - ▶️ **Start:** `mkdir -p $WORK/a08`
> - ✅ **Sprawdzenie:** `./setup/check.sh A08` · rozwiązanie zwinięte na końcu

**Co zrobić:** Dashboard w Grafanie „FTI” (tytuł dokładnie `FTI`): QPS per wersja modelu, p50/p95, error rate, wiek cech, ostatnie Joby treningowe — zapytania z kroku 2. Wyeksportuj JSON (Share → Export) do `$WORK/a08/dashboard-fti.json` i wgraj go jako ConfigMap jak niżej (podmień ścieżkę), potem `./setup/check.sh A08`.

<details><summary>Rozwiązanie</summary>

`03-advanced/08-observability/solution/dashboard-fti.json` — import ręczny (Dashboards → New → Import) albo przez sidecar Grafany:

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl -n monitoring create configmap fti-dashboard --from-file=fti.json=03-advanced/08-observability/solution/dashboard-fti.json \
  --dry-run=client -o yaml | kubectl label --local -f - grafana_dashboard=1 -o yaml | kubectl apply -f -
# Grafana -> Dashboards -> FTI (po ~30 s)
```
</details>

### 5. EXTRA: logi (Loki + Alloy)

— logi: Loki + Alloy i zapytanie `{namespace="ml", app="training"} |= "accuracy"`.

▶️ **Wklej do terminala:**
```sh
helm upgrade --install --wait -n monitoring --repo https://grafana.github.io/helm-charts loki loki --version 7.7.0 -f 03-advanced/08-observability/solution/loki-values.yaml
helm upgrade --install --wait -n monitoring --repo https://grafana.github.io/helm-charts alloy alloy --version 1.16.0 -f 03-advanced/08-observability/solution/alloy-values.yaml
kubectl apply -f 03-advanced/08-observability/solution/loki-datasource.yaml      # źródło Loki w Grafanie
kubectl apply -f 03-advanced/07-security-psa-vap/solution/train-job-restricted.yaml   # coś, co loguje accuracy
# Grafana -> Explore -> Loki: {namespace="ml", app="training"} |= "accuracy"
```
Alloy działa jako Deployment z `loki.source.kubernetes` — czyta logi przez API, bez montowania `/var/log` węzła.

### 6. EXTRA: metryki GPU (DCGM)

— GPU: na klastrze z A03/A04 DCGM exporter (`DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`) + ServiceMonitor.

▶️ **Wklej do terminala:**
```sh
# po instalacji fake-gpu-operatora z A03 (ma własny nvidia-dcgm-exporter):
kubectl apply -f 03-advanced/08-observability/solution/dcgm-servicemonitor.yaml
kubectl -n default apply -f 03-advanced/03-gpu-fake-operator/gpu-train-job.yaml   # w ml blokuje to PSA/VAP z A07
```

▶️ **Wklej w Prometheus → Graph / Grafana → Explore:**
```promql
DCGM_FI_DEV_GPU_UTIL                          # 4 GPU; zajęte: 100, z etykietą exported_pod
sum by (exported_pod) (DCGM_FI_DEV_FB_USED)   # pamięć GPU per Pod
```

## Pytania
1. Które z tych alertów wykryją *dryft danych* lub spadek jakości modelu? (Żaden — to monitoring ML: Evidently/whylogs, opóźnione etykiety, metryki jakości jako metryki Prometheusa z Joba ewaluacyjnego.)
2. PodMonitor vs ServiceMonitor — kiedy który?
3. Jakie metryki LLM (vLLM/TGI) są kluczowe: TTFT, tokens/s, `num_requests_waiting`, KV-cache usage — jak je zebrać?

## Sprzątanie

**Usuń** — tylko jeśli **nie** idziesz do A10 albo brakuje RAM (stack ~3 GB) — inaczej zostaw:

▶️ **Wklej do terminala:**
```sh
helm uninstall alloy loki kube-prometheus-stack -n monitoring
kubectl delete -f 03-advanced/08-observability/podmonitor.yaml -f 03-advanced/08-observability/prometheus-rules.yaml --ignore-not-found
kubectl delete ns monitoring
```

**Zostaw:**
- `monitoring` → A10 (alerty i dashboard są częścią capstone). A10 tworzy `ml` od nowa — PodMonitor (żyje w `ml`) zaaplikuj wtedy ponownie: `kubectl apply -f 03-advanced/08-observability/podmonitor.yaml`
