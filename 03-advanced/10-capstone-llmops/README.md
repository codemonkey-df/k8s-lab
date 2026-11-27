# A10 — Capstone: platforma FTI + LLM w jednym klastrze

**Czas:** 2–4 h (bez gotowców — to sprawdzian)  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/10-capstone-llmops/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Złożyć wszystko, co było, w działającą „mini-platformę ML” i dołożyć serwowanie LLM z bramką ewaluacyjną.

```
                         ┌──────────── namespace ml (quota, PSA restricted, netpol, VAP) ─────────────┐
 CronJob features ──► features PVC ──► Job train (bramka) ──► model-store/vN ──► inference (HPA, PDB)
          └──────────► Redis (StatefulSet) ◄───────────────────────────────────────────┘     │
                                                                                            │
 Gateway ml-gateway (infra) ── ml.…/predict ── wine.… (canary/shadow v1/v2) ────────────────┘
          └──────────────── llm.…/v1 ──► namespace llm: Ollama (PVC z modelem) ◄── Job llm-eval
 monitoring: PodMonitor + alerty (InferenceDown, p95, FeaturesStale, TrainingJobFailed)
```

## Część 1 — LLM serving (gotowe manifesty)

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/10-capstone-llmops/ollama.yaml
kubectl -n llm get pods -w                       # Init (pull ~1 GB) -> Running
kubectl -n llm logs deploy/ollama -c pull-model
curl -s http://llm.127-0-0-1.nip.io/v1/models
curl -s http://llm.127-0-0-1.nip.io/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"llm","messages":[{"role":"user","content":"Explain a Kubernetes Pod in one sentence."}]}'
# "llm" = alias tworzony przez initContainer: MODEL z ConfigMap + num_thread (patrz niżej)
curl -s -o /dev/null -w '%{http_code}\n' http://llm.127-0-0-1.nip.io/api/pull   # 404 — panel admina nie wystawiony
kubectl apply -f 03-advanced/10-capstone-llmops/llm-eval-job.yaml
kubectl -n llm logs -f job/llm-eval              # PASS/FAIL, score=1.00
```
Trzy rzeczy, które wyszły w testach na CPU:
- **wątki:** Ollama ustala liczbę wątków z rdzeni *hosta*, nie z limitu kontenera — w teście laba dawało to 0,3 tok/s (40 s na „hi”). Z `num_thread 6` ~140 tok/s. Stąd alias `llm` z `PARAMETER num_thread` i `requests.cpu: 6` bez limitu CPU,
- **timeout Gatewaya:** Envoy domyślnie ucina żądanie po 15 s (`504 upstream request timeout`) → `timeouts.request: 300s` w HTTPRoute,
- **model:** `qwen2.5:0.5b` oblewa bramkę (`score=0.50`), `qwen2.5:1.5b` przechodzi (`1.00`).

## Część 2 — wymagania (zrób sam, odhaczaj)
**FTI (`ml`)**
- [ ] Jedno polecenie (`kubectl apply -k` albo `helm upgrade --install`) stawia: PVC, feature store, CronJob cech, inference, Service, HTTPRoute, HPA, PDB.
- [ ] Nowy model: Job `train-vN` → przy sukcesie bramki rollout inference na `vN` z `change-cause`; przy porażce inference zostaje na starej wersji.
- [ ] Wdrożenie `vN` jako shadow → canary 10% → 100% (A05), z obserwacją metryk w Grafanie.
- [ ] `ml` ma: ResourceQuota + LimitRange (A02), PSA `restricted` enforce (A07), VAP guardrails (A07), default-deny + przepływy (A06).

**LLM (`llm`)**
- [ ] NetworkPolicy: do Ollamy tylko z Envoya i z Poda `llm-eval`; Ollama bez egress poza DNS **po** pobraniu modelu (jak pogodzić z initContainerem? — podpowiedź: osobny Job pobierający model do PVC i polityka tylko na Pody serwera).
- [ ] Zmiana modelu (`MODEL` w ConfigMap, np. `qwen2.5:1.5b`) → rollout → Job `llm-eval` jako bramka; przy `score < THRESHOLD` powrót do poprzedniego modelu.
- [ ] Ollama dostaje `priorityClassName: inference-critical` i pulę wg zasobu (CPU teraz, GPU na klastrze z A04 — odkomentuj `nvidia.com/gpu`).

**Operacje**
- [ ] Alerty z A08 działają i każdy umiesz wywołać.
- [ ] `kubectl drain` węzła z inference nie powoduje przerwy (PDB + TSC).
- [ ] Runbook (`03-advanced/10-capstone-llmops/solution/RUNBOOK.md`): 5 najczęstszych awarii z A09 → jak rozpoznać i naprawić w tej platformie.

## Rozwiązanie części 2 (sprawdzone)
Postęp: `./setup/check.sh A10`.

<details><summary>Pokaż rozwiązanie</summary>

▶️ **Wklej do terminala:**
```sh
S=03-advanced/10-capstone-llmops/solution     # katalog rozwiązania
# FTI: cała platforma w ml jednym poleceniem (ns z PSA+guardrails, quota, LimitRange, netpol,
# PV/PVC, Redis, CronJob, inference + Service + HTTPRoute + HPA + PDB, PriorityClass, VAP)
kubectl apply -k $S/platform
$S/train.sh v4 && $S/release.sh v4                 # bramka -> release.env -> apply -k -> change-cause
N_ESTIMATORS=1 MAX_DEPTH=1 MIN_ACCURACY=0.99 $S/train.sh v5 ; $S/release.sh v5   # odrzucony, stable bez zmian
kubectl -n ml rollout history deploy/inference

# shadow -> canary -> 100%
N_ESTIMATORS=200 $S/train.sh v6 && $S/candidate.sh v6
kubectl apply -f $S/route-shadow.yaml               # odpowiada stable, kopia do kandydata
kubectl apply -f $S/route-canary.yaml               # 90/10; Grafana: QPS per model_version (A08)
$S/release.sh v6                                  # 100%: stable=v6, route z kustomize, kandydat usunięty

# LLM zamknięty: Ollama bez internetu, model pobiera Job llm-pull (jedyny z egress 443)
kubectl apply -k $S/llm
$S/llm-release.sh qwen2.5:1.5b                    # pull -> restart -> eval -> OK
$S/llm-release.sh qwen2.5:0.5b                    # score 0.50 -> automatyczny powrót do 1.5b
```
Wyniki testu: platforma z zera w ~1 min; v5 odrzucony, stable zostaje na v4; shadow 100 kopii u kandydata, canary 90/10, po release 100% v6; `drain` węzła z inference pod ruchem: 631 żądań, 0 błędów; z `default` do `inference.ml` i `ollama.llm` ruch zablokowany; `ollama pull` w serwerze wisi (brak egress). Alerty: patrz A08 krok 3 (wszystkie 5 wywołane). Runbook: `$S/RUNBOOK.md`.

Uwagi:
- `release.env` jest źródłem prawdy o wersji w produkcji — `kubectl set env` zostałby nadpisany przy następnym `apply -k` (lekcja z I03). W prawdziwym zespole: commit + GitOps (Argo CD/Flux).
- Kandydat ma `app: inference` (netpol, PodMonitor), ale `track: candidate` — Service `inference` wybiera tylko `track: stable`.
- Po `drain` + `uncordon` repliki zostają na jednym węźle (TSC działa tylko przy planowaniu) — `kubectl rollout restart` albo descheduler.
</details>

## Pytania końcowe
1. Co z tej platformy zastąpiłbyś gotowcem w produkcji i czym? (KServe/vLLM production-stack — serving; Kueue — kolejki GPU; Argo Workflows/Kubeflow — pipeline; MLflow — rejestr; Feast — feature store; Argo CD — GitOps)
2. Które elementy są identyczne niezależnie od tych narzędzi? (Pody, sondy, zasoby, Joby, PVC, RBAC, quota, scheduling GPU, Gateway, monitoring — czyli to, co przerobiłeś.)

## Sprzątanie

**Usuń** — koniec ścieżki — klaster, dane i Twoje pliki. `release.sh` zmienia `03-advanced/10-capstone-llmops/solution/platform/release.env` w repo — przywróć `v1`, żeby kolejne przejście startowało od początku:

▶️ **Wklej do terminala:**
```sh
echo MODEL_VERSION=v1 > 03-advanced/10-capstone-llmops/solution/platform/release.env
./setup/down.sh && rm -f ~/.kube/kind-mlops.yaml   # klaster mlops + jego osobny kubeconfig (~/.kube/config nietknięty)
./setup/clean-data.sh    # modele z $LAB_DATA (pliki Podów mają UID 10001 — zwykłe rm nie zadziała)
rm -rf "$WORK"               # Twoje manifesty z ćwiczeń — tylko jeśli chcesz zacząć od zera
```

**Zostaw:**
- `~/.kube/config` (kontekst `default`) — labowy klaster nigdy go nie dotyka
- obraz `fti-lab:0.1` w Dockerze hosta — `./app/build.sh 0.1` przy następnym starcie i tak go odświeży
