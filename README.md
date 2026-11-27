# k8s-lab — Kubernetes dla MLOps/LLMOps

Samodzielne laby Kubernetesa pod kątem administracji platformą ML/LLM.
Konsola + kind, trzy poziomy wejścia: basic → intermediate → advanced.

**Wątek przewodni:** jedna mała aplikacja ML w architekturze **FTI** (Feature → Training → Inference),
która rośnie z każdym labem: od gołego Poda z modelem, przez pipeline Job/CronJob z rejestrem modeli
i feature store, po canary nowego modelu, GPU, monitoring i serwowanie LLM.

```
 F  CronJob feature-pipeline ─► PVC features (offline) ─┬─► T  Job train-vN / Indexed Job HPO ─► PVC model-store/vN
                             └► Redis StatefulSet (online)│                                         │
                                         ▲                └──────────────────────────────┐          ▼
 I  Gateway ─► Service ─► Deployment inference (initContainer pobiera vN, sondy, HPA, PDB) ◄┘
    LLM: Gateway ─► Ollama (CPU) / vLLM (GPU) ◄─ Job llm-eval (bramka jakości)
```

## Start

**Potrzebujesz tylko Dockera** (użytkownik w grupie `docker`). Resztę ogarnia `setup/prereq.sh` — `up.sh` woła go sam:

| Co masz | Co się dzieje |
|---|---|
| nic poza Dockerem | instaluje kind v0.33.0, kubectl v1.37.2, helm v4.3.2 do `~/.local/bin` (bez sudo, z kontrolą SHA-256) |
| już masz kind / kubectl / helm | **używa Twoich** — najwyżej ostrzeże o wersji (kind < 0.24: brak NetworkPolicy; helm < 4: inne flagi) |
| już masz klaster `mlops` | `up.sh` go używa, nie tworzy nowego |
| brak Dockera | zatrzymuje się i podaje polecenia (`get.docker.com` + `usermod -aG docker`) — to jedyny krok z sudo |

Sam test, bez instalowania: `./setup/prereq.sh --check` (sprawdza też CPU/RAM, limity inotify i `/dev/kmsg` w LXC).

▶️ **Wklej do terminala:**
```sh
git clone https://github.com/codemonkey-df/k8s-lab && cd k8s-lab
source setup/env.sh        # w KAŻDYM terminalu: osobny KUBECONFIG=~/.kube/kind-mlops.yaml (+ ~/.local/bin w PATH)
./setup/up.sh              # prereq.sh + klaster kind "mlops": 1 control-plane + 2 workery
./app/build.sh 0.1         # obraz fti-lab:0.1 -> kind load
```
Zasoby: basic ~4 CPU / 8 GB RAM, advanced (monitoring A08, Ollama A10) ~8 CPU / 16 GB.
- Szkoleniowy `~/.kube/config` (kontekst `default`) **nie jest ruszany** — kind pisze do osobnego pliku.
- `$LAB_DATA` (`~/k8s-lab-data`) jest zamontowany we wszystkich węzłach jako `/mnt/shared` → „współdzielony storage” na rejestr modeli. Modele widać z hosta: `ls ~/k8s-lab-data/models`.
- **Wszystkie komendy uruchamiasz z korzenia repo (`k8s-lab/`)** — ścieżki w README są względem niego (np. `kubectl apply -f 01-basic/03-pod/pod.yaml`). Nie robisz `cd` do labów. Od B01 domyślny namespace to `ml`.
- Reset: `./setup/reset-ns.sh` (czyści `ml`), `./setup/down.sh` (usuwa klaster), `./setup/clean-data.sh` (usuwa modele z `$LAB_DATA` — pliki Podów mają UID 10001, zwykłe `rm` nie zadziała).
- Każdy lab: **Cel → Kroki → Zadanie → Pytania → Sprzątanie**.

## Jak pracować
| Oznaczenie | Co robisz |
|---|---|
| ▶️ **Wklej do terminala** | kopiujesz blok i uruchamiasz z korzenia repo (`k8s-lab/`) |
| ### ✍️ Zadanie / #### ✍️ | **piszesz albo zmieniasz YAML sam** — opis w „Co zrobić” |
| 📄 **Wzór** | przykład z laba — tylko czytasz/kopiujesz, **nie zmieniasz** |
| 📝 **Twój plik** (nowy — tworzysz) | plik jeszcze nie istnieje; powstaje w `$WORK/...` (najczęściej przez ▶️ **Start:** = kopia wzoru) |
| 📝 **Twój plik** (masz go z … — zmieniasz) | rozwijasz swój plik z wcześniejszego kroku/laba, np. `$WORK/inference.yaml` |
| ▶️ **Uruchom i sprawdź** | po napisaniu pliku: `apply` + `check.sh` |
| ▶️ **Wklej w Prometheus / Grafana** | zapytanie PromQL do UI, nie do terminala |
| ▸ Rozwiązanie (zwinięte) | zaglądasz dopiero po próbie i `check.sh` |

- **Przykład → Twój manifest.** Lab pokazuje gotowy przykład (`kubectl apply -f ...` i obserwacja), a w krokach oznaczonych ✍️ piszesz albo zmieniasz YAML sam — na bazie przykładu albo tego, co już umiesz z wcześniejszych labów.
- **Swoje pliki trzymasz w `$WORK`** (`work/` w repo, tworzy go `env.sh`), np. `$WORK/b04/canary.yaml`. Pliki w labach zostają przykładami — zawsze możesz zacząć od nowa.
- **Zmiany przez plik, nie przez `kubectl set/edit/patch`.** Manifest inference „rośnie” w jednym pliku `$WORK/inference.yaml` (I03 → I04 → I06 → I07). Polecenia imperatywne zostają tylko tam, gdzie są tematem kroku (szybkie zepsucie, przesuwanie wag w Gatewayu).
- **Sprawdź się:** `./setup/check.sh <lab>` (np. `./setup/check.sh B03`) — ✅/❌ dla każdego wymagania ćwiczenia.
- **Rozwiązania** są zwinięte pod „Rozwiązanie” i leżą w `<lab>/solution/` — zaglądaj po próbie i po `check.sh`.

## Ścieżka

### 01-basic — obiekty podstawowe (≈ 4–5 h)
| Lab | Temat | FTI | Test |
|---|---|---|---|
| [B01](01-basic/01-cluster-kubectl) | kind, kubectl, konteksty, namespace `ml`, `--dry-run -o yaml` | — | ✅ |
| [B02](01-basic/02-image-kind-load) | obraz aplikacji ML, `kind load`, `imagePullPolicy` | F T I | ✅ |
| [B03](01-basic/03-pod) | Pod z serwerem modelu, logs/exec/port-forward, etykiety | I | ✅ |
| [B04](01-basic/04-service) | ClusterIP, NodePort, DNS, EndpointSlice | I | ✅ |
| [B05](01-basic/05-probes-resources) | startup/readiness/liveness dla wolno ładującego się modelu, QoS, OOMKilled | I | ✅ |
| [B06](01-basic/06-deployment-rollout) | Deployment, zero-downtime rollout wersji modelu, rollback | I | ✅ |
| [B07](01-basic/07-configmap-secret) | ConfigMap (env + plik), Secret (HF token) | I | ✅ |

### 02-intermediate — pipeline FTI i wystawienie (≈ 7–8 h)
| Lab | Temat | FTI | Test |
|---|---|---|---|
| [I01](02-intermediate/01-storage-model-registry) | PV/PVC/StorageClass: rejestr modeli (RWX) + offline feature store | F T | ✅ |
| [I02](02-intermediate/02-jobs-fti-pipeline) | CronJob cech, Job treningu z bramką jakości, Indexed Job (HPO), `podFailurePolicy` | F T | ✅ |
| [I03](02-intermediate/03-serving-from-registry) | initContainer pobierający model z rejestru, rollout nowego modelu | T→I | ✅ |
| [I04](02-intermediate/04-statefulset-feature-store) | StatefulSet: Redis jako online feature store | F→I | ✅ |
| [I05](02-intermediate/05-gateway-api) | Gateway API (Envoy Gateway): host/ścieżka, URLRewrite — „API dla modeli” | I | ✅ |
| [I06](02-intermediate/06-hpa-autoscaling) | metrics-server, HPA (i czemu CPU to zła metryka dla LLM) | I | ✅ |
| [I07](02-intermediate/07-rbac-serviceaccounts) | SA automatu MLOps, inference bez tokena, rola data scientist | F T I | ✅ |
| [I08](02-intermediate/08-kustomize-envs) | Kustomize: base + dev/prod, configMapGenerator | I | ✅ |
| [I09](02-intermediate/09-helm) | Helm: cudze charty + własny chart `fti-inference` (GPU/HPA/HTTPRoute) | I | ✅ |

### 03-advanced — administracja platformą ML (≈ 10–14 h)
| Lab | Temat | FTI | Test |
|---|---|---|---|
| [A01](03-advanced/01-scheduling-gpu-pools) | pule CPU/GPU: taints, affinity, TSC, PriorityClass + wywłaszczanie, PDB + drain | T I | ✅ |
| [A02](03-advanced/02-multitenancy-quotas) | namespace zespołu: ResourceQuota (także GPU), LimitRange | T | ✅ |
| [A03](03-advanced/03-gpu-fake-operator) | fake-gpu-operator: `nvidia.com/gpu`, multi-GPU, MIG, quota GPU | T I | ✅ |
| [A04](03-advanced/04-gpu-real-kind) | **prawdziwe GPU** (RTX 4070 Ti SUPER) w kind: GPU Operator, time-slicing, vLLM | I (LLM) | ❌ |
| [A05](03-advanced/05-canary-shadow-models) | header routing, shadow (mirror), canary modelu przez wagi | I | ✅ |
| [A06](03-advanced/06-network-policies) | default deny + przepływy FTI (gateway → inference → feature store) | F I | ✅ |
| [A07](03-advanced/07-security-psa-vap) | securityContext, PSA restricted, VAP: guardrails dla workloadów i Jobów ML | F T I | ✅ |
| [A08](03-advanced/08-observability) | kube-prometheus-stack, PodMonitor, alerty: latencja, świeżość cech, porażki treningu | F T I | ✅ |
| [A09](03-advanced/09-troubleshooting) | 8 zepsutych workloadów ML, `kubectl debug` | — | ✅ |
| [A10](03-advanced/10-capstone-llmops) | capstone: cała platforma + Ollama + Job ewaluacji LLM | F T I | ✅ |

**Test:** ✅ = cały lab (kroki, zadania, EXTRA, rozwiązania w `solution/`) wykonany od początku do końca na kind v0.33.0 / Kubernetes v1.37.0 (2026-11-27); ❌ = jeszcze nie. Data testu jest też w nagłówku każdego laba (pole **Przetestowano**).

## Czego tu nie ma (i dlaczego)
| Temat | Dlaczego poza ścieżką |
|---|---|
| Docker Compose, lokalne demo tracingu | poza Kubernetesem |
| logowanie użytkowników certyfikatem / OIDC | wiedza admina klastra, nie platformy ML; w I07 wystarczą SA + tokeny |
| adnotacje, DaemonSet jako osobny temat | pojawiają się „przy okazji” (change-cause, device-plugin GPU w A03) |
| pisanie własnego operatora / CRD | warto znać pojęcie, ale w ML używasz gotowych operatorów (GPU Operator, Kueue, KServe, KubeRay); patrz pytania w A03/A10 |
| Vault | ciężka instalacja; alternatywy omówione w pytaniach B07/A07 |
| Kubernetes Dashboard, instalacja kubeadm | nie dotyczy kind ani pracy MLOps na gotowym klastrze |

## Co dalej
Kueue (kolejki GPU dla treningu), KServe / vLLM production-stack (serving), Argo Workflows / Kubeflow Pipelines (orkiestracja FTI), KubeRay (trening rozproszony), Argo CD (GitOps dla overlayów z I08), KEDA (skalowanie po kolejce/metrykach LLM).
Każde z nich składa się z obiektów przerobionych w tych labach.

## Struktura
```
k8s-lab/
├── README.md            # ten plik
├── setup/               # prereq.sh, env.sh, up.sh, down.sh, reset-ns.sh, clean-data.sh, check.sh, kind-mlops.yaml.tpl
├── work/                # TWOJE manifesty z ćwiczeń (tworzy env.sh)
├── app/                 # aplikacja FTI: fti/{features,train,serve}.py, Dockerfile, build.sh, pyproject.toml (uv + ruff)
├── 01-basic/            # B01–B07
├── 02-intermediate/     # I01–I09
└── 03-advanced/         # A01–A10
```

Praca nad kodem FTI (opcjonalnie, poza labami): `cd app && uv sync && uv run ruff check . && uv run ruff format --check .` — obraz dalej buduje `./app/build.sh` z `requirements.txt` (wersje trzymaj takie same jak w `pyproject.toml`).
