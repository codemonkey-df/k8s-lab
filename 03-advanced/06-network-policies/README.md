# A06 — NetworkPolicy: kto z kim rozmawia w pipeline FTI

**Czas:** ~50 min  
**Wymaga:** inference + feature-store + feature-pipeline (I03/I04), Gateway (I05). kind ≥ 0.24 — kindnet egzekwuje NetworkPolicy.  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/06-network-policies/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Zamknąć namespace `ml` (default deny) i otworzyć tylko przepływy wynikające z architektury:

```
envoy-gateway-system ──► inference:8080 ──► feature-store:6379 ◄── feature-pipeline
monitoring ────────────► inference:8080 (/metrics)
wszyscy ───────────────► kube-dns:53
```
Model nie powinien móc „zadzwonić do internetu”, a feature store nie powinien być osiągalny z dowolnego Poda.

## Kroki

### 1. Stan wyjściowy — wszystko ze wszystkim

▶️ **Wklej do terminala:**
```sh
kubectl run t --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c 'curl -s -m3 inference/version; echo; nc -zv -w3 feature-store 6379; curl -sI -m3 https://pypi.org | head -1'
```

### 2. Default deny + DNS

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/06-network-policies/default-deny.yaml
curl -s -m3 http://ml.127-0-0-1.nip.io/version || echo ZABLOKOWANE   # gateway też odcięty
```

### ✍️ 3. Zadanie: polityki przepływów FTI

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `03-advanced/06-network-policies/default-deny.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a06/allow-fti.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a06 && cp 03-advanced/06-network-policies/default-deny.yaml $WORK/a06/allow-fti.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A06` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `03-advanced/06-network-policies/default-deny.yaml` napisz `$WORK/a06/allow-fti.yaml` — polityki dla przepływów z diagramu (ingress i egress — przy default deny obie strony muszą się zgadzać). Sprawdź:
- `curl http://ml.127-0-0-1.nip.io/version` ✅, `curl .../predict/entity/42` ✅ (inference → Redis),
- `kubectl create job --from=cronjob/feature-pipeline f-np` ✅ (feature-pipeline → Redis),
- Pod `t` z kroku 1: inference ❌, Redis ❌, internet ❌.
- wszystko naraz: `./setup/check.sh A06`.

<details><summary>Rozwiązanie</summary>

`03-advanced/06-network-policies/solution/allow-fti.yaml`
</details>

### 4. Pułapki do zaobserwowania

- NodePort `localhost:30080` przestał działać — ruch przychodzi z IP węzła, nie z Envoya.
- Job treningowy nie potrzebuje sieci (poza DNS) — sprawdź, że `train-v1` nadal przechodzi.

## Pytania
1. Dlaczego bez polityki `allow-dns` „nic nie działa”, choć IP są osiągalne?
2. `namespaceSelector` + `podSelector` w **jednym** elemencie `from` vs w **dwóch** — różnica?
3. Pod treningowy pobierający dane z S3/HF — jak ograniczyć egress do konkretnych domen? (NetworkPolicy działa na IP/CIDR → Cilium/Calico FQDN policies, egress gateway/proxy)

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- polityki w `ml` → A07 i A08 testują na zamkniętym namespace (A08: `monitoring` jest już wpuszczony do `:8080`)
- skutek uboczny: `localhost:30080` (NodePort) nie działa — od teraz ruch idzie przez Gateway. Wyłączenie wszystkiego: `kubectl delete netpol --all`
