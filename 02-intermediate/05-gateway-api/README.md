# I05 — Gateway API: jeden punkt wejścia do modeli

**Czas:** ~50 min  
**Wymaga:** Service `inference` (B04) z Deploymentem (I03).  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/05-gateway-api/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Wystawić inference przez Gateway API (Envoy Gateway) pod nazwą hosta i ścieżką — tak, jak w produkcji wystawia się wiele modeli za jednym adresem.

## Kroki

### 1. Envoy Gateway (`kubectl apply` z release'u, bez Helma)

▶️ **Wklej do terminala:**
```sh
kubectl apply --server-side -f https://github.com/envoyproxy/gateway/releases/download/v1.9.0/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
kubectl apply -f 02-intermediate/05-gateway-api/envoyproxy-kind.yaml          # hostPort 80/443 na control-plane
kubectl apply -f 02-intermediate/05-gateway-api/gateway.yaml
kubectl wait -n infra --for=condition=Programmed gateway/ml-gateway --timeout=2m
kubectl get gatewayclass,gateway -A
```

### 2. Route do modelu

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/05-gateway-api/httproute.yaml
kubectl get httproute inference -o jsonpath='{.status.parents[0].conditions[*].type}{"\n"}'  # Accepted ResolvedRefs
curl -s http://ml.127-0-0-1.nip.io/version
curl -s -XPOST http://ml.127-0-0-1.nip.io/predict -H 'content-type: application/json' \
  -d '{"instances":[[13.2,1.8,2.1,16,100,2.4,2.6,0.3,1.9,5.6,1.0,3.2,1100]]}'
curl -s -o /dev/null -w '%{http_code}\n' http://ml.127-0-0-1.nip.io/metrics   # 404 — nie wystawiamy
```
Bez DNS (nip.io): `curl -H 'Host: ml.127-0-0-1.nip.io' http://localhost/version`.

### ✍️ 3. Zadanie: API dla modeli

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/05-gateway-api/httproute.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/i05/httproute-models.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/i05 && cp 02-intermediate/05-gateway-api/httproute.yaml $WORK/i05/httproute-models.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I05` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `02-intermediate/05-gateway-api/httproute.yaml` napisz `$WORK/i05/httproute-models.yaml` — „API dla modeli” na hoście `api.127-0-0-1.nip.io`: `/models/wine/predict` → `inference:/predict`, `/models/wine/version` → `inference:/version` (filtr `URLRewrite` z `ReplacePrefixMatch`) + nagłówek odpowiedzi `x-served-by: fti-inference` (filtr `ResponseHeaderModifier`). Inne ścieżki na tym hoście → 404. Sprawdź: `./setup/check.sh I05`.

<details><summary>Rozwiązanie</summary>

`02-intermediate/05-gateway-api/solution/httproute-models.yaml`
</details>

### 4. EXTRA: listener HTTPS z certyfikatem self-signed

▶️ **Wklej do terminala:**
```sh
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=ml.127-0-0-1.nip.io" -addext "subjectAltName=DNS:ml.127-0-0-1.nip.io"
kubectl -n infra create secret tls ml-tls --cert=/tmp/tls.crt --key=/tmp/tls.key
# w kopii (cp 02-intermediate/05-gateway-api/gateway.yaml $WORK/i05/) dopisz listener: name: https, protocol: HTTPS, port: 443,
#   tls: { mode: Terminate, certificateRefs: [{ kind: Secret, name: ml-tls }] }
curl -kv https://ml.127-0-0-1.nip.io/version 2>&1 | grep -E 'subject|HTTP/'
```

## Pytania
1. Role w Gateway API: kto zarządza `GatewayClass`, `Gateway`, `HTTPRoute`? Jak to mapuje się na zespół platformy vs zespół ML?
2. Dlaczego `/metrics` nie powinien być dostępny przez Gateway?
3. Czym są GAIE (Gateway API Inference Extension, `InferencePool`) i po co routing „świadomy modelu” dla LLM?

## Sprzątanie

**Usuń** — opcjonalnie route z zadania — nic dalej z niego nie korzysta:

▶️ **Wklej do terminala:**
```sh
kubectl delete -f $WORK/i05/httproute-models.yaml --ignore-not-found
```

**Zostaw:**
- Envoy Gateway (`envoy-gateway-system`), Gateway `ml-gateway` (`infra`) i HTTPRoute `inference` → A05, A06, A08, A10 (`ml.127-0-0-1.nip.io`)
- Secret `ml-tls` / listener HTTPS z EXTRA nie przeszkadzają
