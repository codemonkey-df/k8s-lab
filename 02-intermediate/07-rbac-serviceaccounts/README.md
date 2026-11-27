# I07 — RBAC i ServiceAccount: kto może trenować, kto tylko patrzy

**Czas:** ~45 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/07-rbac-serviceaccounts/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Dać minimalne uprawnienia trzem „aktorom” platformy ML:

| Aktor | Tożsamość | Może |
|---|---|---|
| automat MLOps (Argo/Airflow) | SA `pipeline-runner` | tworzyć/kasować Joby, czytać Pody i logi w `ml` |
| serwer inference | SA `inference` | nic (bez tokena) |
| data scientist | SA/user `data-scientist` | oglądać `ml`, exec/port-forward, bez Secretów |

## Kroki

### 1. Role i ServiceAccount automatu

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/07-rbac-serviceaccounts/rbac.yaml
kubectl auth can-i create jobs --as=system:serviceaccount:ml:pipeline-runner        # yes
kubectl auth can-i delete deployments --as=system:serviceaccount:ml:pipeline-runner # no
kubectl auth can-i --list --as=system:serviceaccount:ml:pipeline-runner
```

### 2. Automat w akcji

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 02-intermediate/07-rbac-serviceaccounts/trigger-pod.yaml
kubectl get pod retrain-trigger -w   # initContainery po kolei, na końcu Error (celowo: Forbidden)
kubectl logs retrain-trigger -c create-job     # job.batch/retrain-from-pod created
kubectl logs retrain-trigger -c list-jobs
kubectl logs retrain-trigger -c try-delete-inference   # Forbidden
```

### ✍️ 3. Inference bez tokena

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (masz go z I03 — zmieniasz): `$WORK/inference.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I07`

**Co zrobić:** W `$WORK/inference.yaml` dodaj `serviceAccountName: inference` (SA z `02-intermediate/07-rbac-serviceaccounts/rbac.yaml` ma `automountServiceAccountToken: false`):

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl apply -f $WORK/inference.yaml && kubectl rollout status deploy/inference
kubectl exec deploy/inference -c server -- ls /var/run/secrets/kubernetes.io/serviceaccount   # brak
```

### ✍️ 4. Zadanie: rola data-scientist

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/07-rbac-serviceaccounts/rbac.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/i07/data-scientist.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/i07 && cp 02-intermediate/07-rbac-serviceaccounts/rbac.yaml $WORK/i07/data-scientist.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh I07` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `02-intermediate/07-rbac-serviceaccounts/rbac.yaml` napisz `$WORK/i07/data-scientist.yaml` — SA `data-scientist` (wbudowana ClusterRole `view` przez RoleBinding + własna Role na `pods/exec`, `pods/portforward`). Sprawdź `can-i get secrets`, `can-i create pods --subresource=exec` (uwaga: forma `pods/exec` w `can-i` zwraca mylące `no`), `can-i delete jobs`. Sprawdź: `./setup/check.sh I07` (sprawdza też krok 3).

<details><summary>Rozwiązanie</summary>

`02-intermediate/07-rbac-serviceaccounts/solution/data-scientist.yaml`
`02-intermediate/07-rbac-serviceaccounts/solution/inference.yaml`
</details>

### 5. Zaloguj się „jako” SA (kubeconfig z tokenem)

▶️ **Wklej do terminala:**
```sh
TOKEN=$(kubectl create token data-scientist --duration=1h)
kubectl config set-credentials data-scientist --token="$TOKEN"
kubectl config set-context ds --cluster=kind-mlops --user=data-scientist --namespace=ml
kubectl --context ds get pods                       # OK
kubectl --context ds get secrets                    # Forbidden
kubectl --context ds exec deploy/inference -- id    # OK (Role debug-pods)
kubectl config delete-context ds ; kubectl config delete-user data-scientist
```
⚠️ Samo `kubectl --token=$TOKEN get secrets` **nie** sprawdza uprawnień SA: kubeconfig kind ma certyfikat
admina, a API server uwierzytelnia certyfikatem przed tokenem, więc zobaczysz sekrety. Tak wyszło przy teście laba.

## Pytania
1. Role vs ClusterRole; RoleBinding do ClusterRole — jaki ma zasięg?
2. Dlaczego `pods/exec` to w praktyce uprawnienie „prawie admin” do danych w Podzie?
3. Jak w chmurze Pod treningowy dostaje dostęp do S3 bez kluczy w Secret? (IRSA / Workload Identity — SA zmapowane na rolę IAM)

## Sprzątanie

**Usuń** — Pod automatu i Job, który utworzył — tylko demo uprawnień (kontekst `ds` usunąłeś w kroku 5):

▶️ **Wklej do terminala:**
```sh
kubectl delete pod retrain-trigger --ignore-not-found
kubectl delete job retrain-from-pod --ignore-not-found
```

**Zostaw:**
- `02-intermediate/07-rbac-serviceaccounts/rbac.yaml` — **zwłaszcza SA `inference`**: Deployment z niej korzysta, bez SA nowe Pody nie powstaną (np. przy rolloucie w A07)
- SA/Role `data-scientist` nie przeszkadzają
