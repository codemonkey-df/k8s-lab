# B06 — Deployment: wersjonowanie i rollout modelu

**Czas:** ~45 min  
**Wymaga:** Service `inference` z B04.  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/06-deployment-rollout/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Serwować model przez Deployment, wypuszczać nową wersję modelu bez przestoju, cofać złą wersję.

## Kroki

### 1. Deployment

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 01-basic/06-deployment-rollout/deployment.yaml
kubectl get deploy,rs,pods -l app=inference
kubectl rollout status deploy/inference
```

### 2. Ruch w tle (drugi terminal) — zobaczysz, która wersja/Pod odpowiada

▶️ **Wklej do terminala:**
```sh
while true; do curl -s localhost:30080/version | cut -c1-80; sleep 0.5; done
```

### ✍️ 3. Nowa wersja modelu — przez plik

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `01-basic/06-deployment-rollout/deployment.yaml`
> - 📝 **Twój plik** (kopia przykładu — zmieniasz): `$WORK/b06/deployment.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/b06 && cp 01-basic/06-deployment-rollout/deployment.yaml $WORK/b06/`
> - ✅ **Sprawdzenie:** `./setup/check.sh B06`

**Co zrobić:** Nowa „wersja modelu” (tu tylko zmiana env, w I03 prawdziwy nowy model) — **przez plik**, tak jak w CI/GitOps:

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
mkdir -p $WORK/b06 && cp 01-basic/06-deployment-rollout/deployment.yaml $WORK/b06/
# w $WORK/b06/deployment.yaml zmień: MODEL_VERSION -> baked-1, change-cause -> "model baked-1"
kubectl diff -f $WORK/b06/deployment.yaml      # dokładnie te 2 zmiany
kubectl apply -f $WORK/b06/deployment.yaml
kubectl rollout status deploy/inference
kubectl rollout history deploy/inference
kubectl get rs -l app=inference          # stary RS z 0 replik = gotowość do rollbacku
./setup/check.sh B06
```
W pętli z kroku 2: brak błędów w trakcie (maxUnavailable: 0 + readiness + `preStop`).
Eksperyment: usuń `lifecycle.preStop` i powtórz rollout, licząc kody HTTP
(`curl -s -o /dev/null -w '%{http_code} %{errormsg}\n'`). Kończący się Pod może jeszcze dostać ruch,
zanim zniknie z endpointów — `preStop` daje kube-proxy czas na aktualizację reguł.
Uwaga: w pierwszej sekundzie po **utworzeniu** Deploymentu możesz zobaczyć `Connection reset by peer`.
To nie rollout: Service bez endpointów ma w kube-proxy regułę REJECT, która znika z ~1 s opóźnieniem.
Uruchom pętlę dopiero po chwili. Przy teście: 7 rolloutów × 120 żądań, 0 błędów.

### 4. Zła wersja — obraz, który nie istnieje

▶️ **Wklej do terminala:**
```sh
kubectl set image deploy/inference server=fti-lab:9.9
kubectl rollout status deploy/inference --timeout=30s   # utknie
kubectl get pods -l app=inference                       # stare Pody nadal serwują!
kubectl rollout undo deploy/inference
kubectl rollout undo deploy/inference --to-revision=1   # albo do konkretnej rewizji
kubectl diff -f $WORK/b06/deployment.yaml   # po undo do rewizji 1 klaster != plik (baked-0 vs baked-1)
kubectl apply -f $WORK/b06/deployment.yaml  # plik = źródło prawdy
```
`set image` jest tu celowo imperatywny — szybkie zepsucie. Po `rollout undo` zawsze porównaj klaster z plikiem (`kubectl diff`).

### 5. Skalowanie i samoleczenie

▶️ **Wklej do terminala:**
```sh
kubectl scale deploy/inference --replicas=4
kubectl describe svc inference | grep Endpoints
kubectl delete pod -l app=inference --wait=false ; kubectl get pods -l app=inference -w
kubectl scale deploy/inference --replicas=2
```

## ✍️ Zadanie

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (masz go z kroku 3 — zmieniasz): `$WORK/b06/deployment.yaml`

**Co zrobić:** Porównaj strategie: w `$WORK/b06/deployment.yaml` przełącz na `strategy.type: Recreate` (usuń `rollingUpdate` — `kubectl apply` odrzuci Recreate z rollingUpdate) i powtórz krok 3 (zmień wersję na `baked-2`) z pętlą z kroku 2. Kiedy `Recreate` ma sens w ML? (Podpowiedź: model zajmuje całe GPU i dwie wersje nie zmieszczą się naraz.)

## Pytania
1. Co to `revisionHistoryLimit` i jaki ma związek z rollbackiem?
2. Dlaczego `maxUnavailable: 0` bez readiness probe nie daje zero-downtime?
3. Co z selektorem — czy można go zmienić w istniejącym Deploymencie?

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- Deployment `inference` (z `$WORK/b06/deployment.yaml`) → B07 go rozbudowuje; jeśli zostawiłeś `Recreate` z zadania, przywróć `RollingUpdate` (B07 o tym przypomina)
