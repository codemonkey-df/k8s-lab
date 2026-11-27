# B05 — Probes i zasoby: model, który długo się ładuje

**Czas:** ~45 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/05-probes-resources/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Poprawnie skonfigurować sondy dla serwera modelu (startup / readiness / liveness) i zasoby (requests/limits, klasy QoS). Zobaczyć OOMKilled.

## Dlaczego to ważne dla MLOps/LLMOps
LLM ładuje się do pamięci/GPU od kilkudziesięciu sekund do kilku minut. Źle ustawiona liveness probe zabija Pod w trakcie ładowania → nieskończony `CrashLoopBackOff`. Brak readiness → ruch trafia do Poda bez modelu (5xx). Brak limitu pamięci → jeden model zjada węzeł.

| Sonda | Pytanie | Skutek porażki | Endpoint |
|---|---|---|---|
| startup | czy już wystartował? | restart po przekroczeniu progu | `/ready` |
| readiness | czy przyjmować ruch? | Pod znika z Endpoints | `/ready` |
| liveness | czy proces nie zawisł? | restart kontenera | `/healthz` |

## Kroki

### 1. Bez sond — Pod jest `Running 1/1` od razu, choć modelu jeszcze nie ma

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 01-basic/05-probes-resources/slow-model.yaml
kubectl get pod slow-model -w
kubectl port-forward pod/slow-model 8081:8080 &  sleep 2
curl -s localhost:8081/ready ; kill %1        # {"ready":false} mimo READY 1/1
kubectl delete pod slow-model
```

### ✍️ 2. Zadanie: sondy i zasoby

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `01-basic/05-probes-resources/slow-model.yaml`
> - 📝 **Twój plik** (kopia przykładu — dopisujesz): `$WORK/b05/slow-model.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/b05 && cp 01-basic/05-probes-resources/slow-model.yaml $WORK/b05/`
> - ✅ **Sprawdzenie:** `./setup/check.sh B05` · rozwiązanie zwinięte na końcu

**Co zrobić:** Skopiuj przykład (`mkdir -p $WORK/b05 && cp 01-basic/05-probes-resources/slow-model.yaml $WORK/b05/`) i dopisz w nim sondy i zasoby (wymagania w tabeli wyżej, start do ~2,5 min).

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl apply -f $WORK/b05/slow-model.yaml
kubectl get pod slow-model -w           # READY 0/1 -> 1/1 po ~40 s, RESTARTS 0
./setup/check.sh B05
```

<details><summary>Rozwiązanie</summary>

`01-basic/05-probes-resources/solution/slow-model.yaml`
</details>

### ✍️ 3. Liveness bez startupProbe

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): Twój `$WORK/b05/slow-model.yaml` z kroku 2
> - 📝 **Twój plik** (nowy — tworzysz (kopia Twojego pliku)): `$WORK/b05/slow-model-bad.yaml`
> - ▶️ **Start:** `cp $WORK/b05/slow-model.yaml $WORK/b05/slow-model-bad.yaml`

**Co zrobić:** Sprawdź, co się stanie, gdy liveness bez startupProbe ma za mały próg. W kopii `$WORK/b05/slow-model.yaml` (np. jako `slow-model-bad.yaml`) ustaw `livenessProbe` na `/ready`, `failureThreshold: 2`, bez startupProbe — obserwuj `RESTARTS`.

### 4. Klasy QoS

▶️ **Wklej do terminala:**
```sh
kubectl get pod slow-model -o jsonpath='{.status.qosClass}{"\n"}'   # Burstable
```

#### ✍️ Zmień klasę QoS

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (masz go z kroku 2 — zmieniasz): `$WORK/b05/slow-model.yaml`

**Co zrobić:** Zmień w swoim pliku tak, by był `Guaranteed` (requests == limits dla CPU i pamięci) albo `BestEffort` (brak zasobów). Pod ma niezmienne `resources` → `kubectl delete pod slow-model` i `apply` od nowa.

### 5. OOMKilled

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 01-basic/05-probes-resources/oom.yaml
kubectl get pod oom -w
kubectl describe pod oom | grep -A3 'Last State\|State:'   # Reason: OOMKilled, exit 137
```

## Pytania
1. Dlaczego liveness **nie** powinna sprawdzać połączenia z bazą / feature store?
2. Który Pod zostanie wyrzucony pierwszy przy braku pamięci na węźle: BestEffort, Burstable czy Guaranteed?
3. Limit CPU → throttling (wolniejsza inferencja), limit pamięci → OOMKill. Jaką politykę przyjmiesz dla serwera modelu?

## Sprzątanie

**Usuń** — Pody demonstracyjne — żaden kolejny lab ich nie używa:

▶️ **Wklej do terminala:**
```sh
kubectl delete pod slow-model oom --ignore-not-found
```

**Zostaw:**
- nic z tego laba nie jest potrzebne dalej
