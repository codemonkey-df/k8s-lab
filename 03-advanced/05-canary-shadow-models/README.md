# A05 — Canary, A/B i shadow dla modeli (Gateway API)

**Czas:** ~50 min  
**Wymaga:** modele `v1` i `v2` w rejestrze (I02/I03), Gateway `ml-gateway` (I05).  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/05-canary-shadow-models/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Wypuścić nowy model bezpiecznie — trzy strategie, które w MLOps stosuje się częściej niż zwykły rolling update:

| Strategia | Ruch użytkowników na v2 | Do czego |
|---|---|---|
| **header routing** | 0% (tylko testerzy z nagłówkiem) | smoke test na produkcji |
| **shadow / mirror** | 0% (kopia, odpowiedź odrzucana) | porównanie predykcji i latencji na prawdziwym ruchu |
| **canary (weight)** | 10% → 50% → 100% | stopniowe przełączenie z obserwacją metryk |

## Kroki

### 1. Dwie wersje modelu i canary 90/10

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/05-canary-shadow-models/models.yaml
kubectl get pods -l app=wine -L version,track
kubectl apply -f 03-advanced/05-canary-shadow-models/httproute-canary.yaml
./03-advanced/05-canary-shadow-models/measure.sh                                # ~90 v1 / ~10 v2
./03-advanced/05-canary-shadow-models/measure.sh -H 'x-model-version: v2'       # 100 v2
```

### 2. Przesuwanie ruchu bez restartów Podów

▶️ **Wklej do terminala:**
```sh
kubectl patch httproute wine --type=json -p='[
  {"op":"replace","path":"/spec/rules/1/backendRefs/0/weight","value":50},
  {"op":"replace","path":"/spec/rules/1/backendRefs/1/weight","value":50}]'
./03-advanced/05-canary-shadow-models/measure.sh
kubectl get pods -l app=wine            # RESTARTS bez zmian — routing zmienia Envoy
```

### ✍️ 3. Zadanie — shadow

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `03-advanced/05-canary-shadow-models/httproute-canary.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a05/httproute-shadow.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a05 && cp 03-advanced/05-canary-shadow-models/httproute-canary.yaml $WORK/a05/httproute-shadow.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A05` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `03-advanced/05-canary-shadow-models/httproute-canary.yaml` napisz `$WORK/a05/httproute-shadow.yaml` — route, żeby 100% odpowiedzi szło z v1, a **kopia** każdego żądania trafiała do v2 (filtr `RequestMirror`). Sprawdź w logach, że v2 dostaje ruch, a `./03-advanced/05-canary-shadow-models/measure.sh` pokazuje tylko v1:

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl logs -l version=v2 -f | grep predict
./setup/check.sh A05
```

<details><summary>Rozwiązanie</summary>

`03-advanced/05-canary-shadow-models/solution/httproute-shadow.yaml`
</details>

### ✍️ 4. Promocja v2 na 100%

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `03-advanced/05-canary-shadow-models/httproute-canary.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a05/httproute-promote.yaml`
> - ▶️ **Start:** `cp 03-advanced/05-canary-shadow-models/httproute-canary.yaml $WORK/a05/httproute-promote.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A05` · rozwiązanie zwinięte na końcu

**Co zrobić:** Promocja: napisz `$WORK/a05/httproute-promote.yaml` (v2 = 100%), v1 na zero (zostaje na szybki rollback = poprzedni plik route), po okresie obserwacji usuń v1:

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl apply -f $WORK/a05/httproute-promote.yaml
./03-advanced/05-canary-shadow-models/measure.sh                                   # 100 v2
kubectl scale deploy wine-v1 --replicas=0
./setup/check.sh A05                       # teraz sprawdza promocję
```

<details><summary>Rozwiązanie</summary>

`03-advanced/05-canary-shadow-models/solution/httproute-promote.yaml`
</details>

## Pytania
1. Czym canary na poziomie Gateway różni się od rolling update Deploymentu (B06)?
2. Jakie metryki obserwować w canary modelu, a jakich nie widać od razu? (latencja/błędy — od razu; jakość predykcji — dopiero z opóźnionymi etykietami)
3. Kto automatyzuje kroki 10→50→100 z analizą metryk? (Argo Rollouts, Flagger, KServe canaryTrafficPercent)

## Sprzątanie

**Usuń** — dwie wersje modelu `wine` i ich route — dalej nieużywane, 3 Pody mniej:

▶️ **Wklej do terminala:**
```sh
kubectl delete -f 03-advanced/05-canary-shadow-models/models.yaml
kubectl delete httproute wine --ignore-not-found
```

**Zostaw:**
- nic z tego laba nie jest potrzebne dalej (wzorzec shadow/canary wraca w A10 na inference)
