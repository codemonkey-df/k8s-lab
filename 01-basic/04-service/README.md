# B04 — Service: stały adres modelu

**Czas:** ~30 min  
**Wymaga:** Pod `inference` z B03.  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/04-service/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Dać serwerowi inference stały adres (ClusterIP + DNS), wystawić go na zewnątrz (NodePort) i zrozumieć, jak Service znajduje Pody (selektor → EndpointSlice).

## Kroki

### 1. Service dla Poda inference

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 01-basic/04-service/service.yaml
kubectl get svc,endpointslices -l part-of=fti
kubectl describe svc inference      # Endpoints: <IP Poda>:8080
```

### 2. Klient wewnątrz klastra (np. aplikacja, która woła model)

▶️ **Wklej do terminala:**
```sh
kubectl run client --image=curlimages/curl:8.23.0 --rm -it --restart=Never -- sh
#  curl -s inference/version
#  curl -s inference.ml.svc.cluster.local/version
#  cat /etc/resolv.conf          # search ml.svc.cluster.local ...
```

### 3. Z hosta przez NodePort (mapowanie 30080 w kind)

▶️ **Wklej do terminala:**
```sh
curl -s localhost:30080/version
```

### 4. `port-forward` do Service (najwygodniejsze w debugowaniu)

▶️ **Wklej do terminala:**
```sh
kubectl port-forward svc/inference 8080:80
```

### 5. Zepsuj selektor i obserwuj

▶️ **Wklej do terminala:**
```sh
kubectl label pod inference app=inference-x --overwrite
kubectl get endpointslices -l kubernetes.io/service-name=inference   # brak endpointów
curl -s localhost:30080/version                                      # timeout / connection refused
kubectl label pod inference app=inference --overwrite
```

### ✍️ 6. Ćwiczenie — Service tylko dla canary

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `01-basic/03-pod/pod.yaml` (Pod) i `01-basic/04-service/service.yaml` (Service)
> - 📝 **Twój plik** (nowy — tworzysz, dwa obiekty rozdzielone `---`): `$WORK/b04/canary.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/b04 && cp 01-basic/03-pod/pod.yaml $WORK/b04/canary.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh B04` · rozwiązanie zwinięte na końcu

**Co zrobić:** Napisz `$WORK/b04/canary.yaml` z dwoma obiektami (`---`):
- Pod `inference-canary` na bazie `01-basic/03-pod/pod.yaml`: etykiety `app: inference`, `part-of: fti`, **`track: canary`**, readinessProbe na `/ready`,
- Service `inference-canary` na bazie `01-basic/04-service/service.yaml`: ClusterIP, port 80 → nazwany port `http`, selektor wybierający **tylko** Pody `track: canary`.

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl apply -f $WORK/b04/canary.yaml
kubectl get endpointslices -l 'kubernetes.io/service-name in (inference,inference-canary)'
./setup/check.sh B04        # inference: 2 endpointy (oba Pody!), inference-canary: 1
kubectl delete -f $WORK/b04/canary.yaml   # przed B06 — inaczej Service inference dalej wysyła ruch do canary
```
Wniosek: selektor Service to zwykłe zapytanie po etykietach — `inference` objął też canary. Jak to rozdzielić? (w A10: `track: stable` / `track: candidate`)

<details><summary>Rozwiązanie</summary>

`01-basic/04-service/solution/canary.yaml`
</details>

## Pytania
1. `port` vs `targetPort` vs `containerPort` vs `nodePort` — co jest czym?
2. Dlaczego warto używać **nazwanego** portu (`targetPort: http`)?
3. Do czego służy Service bez selektora / typu `ExternalName` (np. zewnętrzny vector DB, API modelu u dostawcy)?

## Sprzątanie

**Usuń** — canary z ćwiczenia — inaczej Service `inference` dalej wysyła mu część ruchu w B06; goły Pod `inference` — w B06 zastąpi go Deployment z tymi samymi etykietami:

▶️ **Wklej do terminala:**
```sh
kubectl delete -f $WORK/b04/canary.yaml --ignore-not-found
kubectl delete pod inference
```

**Zostaw:**
- Service `inference` i `inference-nodeport` → B06–I06 (`localhost:30080`), Gateway w I05 też celuje w `inference`
