# B07 — ConfigMap i Secret: konfiguracja modelu i klucze API

**Czas:** ~40 min  
**Wymaga:** Deployment `inference` z B06.  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/07-configmap-secret/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Wyjąć konfigurację z manifestu Deploymentu do ConfigMap (env i plik), a dane wrażliwe (token do Hugging Face / klucz API LLM) do Secret.

## Kroki

### 1. ConfigMap

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 01-basic/07-configmap-secret/configmap.yaml
kubectl describe cm inference-config
```

### ✍️ 2. Zadanie A: ConfigMap jako env i plik

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `01-basic/07-configmap-secret/configmap.yaml` (nazwy kluczy)
> - 📝 **Twój plik** (masz go z B06 — zmieniasz): `$WORK/b06/deployment.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh B07`

**Co zrobić:** W swoim `$WORK/b06/deployment.yaml` z B06 (przywróć `RollingUpdate`, jeśli robiłeś zadanie z `Recreate`) usuń `env` i podepnij ConfigMap:
- `envFrom.configMapRef` (wszystkie klucze jako env),
- klucz `serving.json` jako plik `/etc/fti/serving.json` (volume `configMap` + `items`).
Sprawdź: `kubectl logs deploy/inference | head` (`LOG_LEVEL has value DEBUG`), `kubectl exec deploy/inference -- cat /etc/fti/serving.json`.

### ✍️ 3. Zmiana ConfigMap w locie

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `01-basic/07-configmap-secret/configmap.yaml`
> - 📝 **Twój plik** (kopia przykładu — zmieniasz): `$WORK/b07/configmap.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/b07 && cp 01-basic/07-configmap-secret/configmap.yaml $WORK/b07/`

**Co zrobić:** Zmień w kopii (`mkdir -p $WORK/b07 && cp 01-basic/07-configmap-secret/configmap.yaml $WORK/b07/`) `LOG_LEVEL: INFO` i `threshold` → `kubectl apply -f $WORK/b07/configmap.yaml`. Po ~1 min:
- plik w wolumenie **się zmienił**, env **nie** (env czytane tylko przy starcie),
- `kubectl rollout restart deploy/inference` → nowe Pody mają nowe env.

### 4. Secret

▶️ **Wklej do terminala:**
```sh
kubectl create secret generic hf-token --from-literal=HF_TOKEN=hf_fake_123 --dry-run=client -o yaml | tee /dev/stderr | kubectl apply -f -
kubectl get secret hf-token -o jsonpath='{.data.HF_TOKEN}' | base64 -d ; echo
```

#### ✍️ Zadanie B: token z Secretu

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): Secret `hf-token` z kroku 1 (już w klastrze)
> - 📝 **Twój plik** (masz go z zadania A — zmieniasz): `$WORK/b06/deployment.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh B07` · rozwiązanie zwinięte na końcu

**Co zrobić:** Wstrzyknij `HF_TOKEN` do Deploymentu przez `env.valueFrom.secretKeyRef` (w tym samym pliku). Sprawdź `kubectl exec deploy/inference -- printenv HF_TOKEN`.

▶️ **Wklej do terminala:**
```sh
kubectl apply -f $WORK/b06/deployment.yaml
./setup/check.sh B07
```

<details><summary>Rozwiązanie</summary>

`01-basic/07-configmap-secret/solution/deployment.yaml`
</details>

## Pytania
1. Czy Secret jest zaszyfrowany? Kto może go odczytać? (→ RBAC w I07, szyfrowanie etcd przez `EncryptionConfiguration`)
2. Jakie są alternatywy dla trzymania sekretów w Git? (Vault, SOPS, Sealed Secrets, External Secrets Operator)
3. Jak automatycznie restartować Pody po zmianie ConfigMap? (Reloader, hash w adnotacji — robi to Helm/Kustomize)

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- Deployment `inference` → w I03 i tak zostanie usunięty i utworzony od nowa z rejestru modeli
- ConfigMap `inference-config` i Secret `hf-token` — dalej nieużywane, ale nie przeszkadzają (usunięcie: `kubectl delete cm inference-config ; kubectl delete secret hf-token`)
