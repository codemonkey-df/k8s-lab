# A07 — Bezpieczeństwo: securityContext, Pod Security Admission, ValidatingAdmissionPolicy

**Czas:** ~60 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/07-security-psa-vap/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
1. Utwardzić serwer modelu do poziomu PSA `restricted`.
2. Włączyć PSA na namespace i zobaczyć, co w pipeline łamie zasady (Redis!).
3. Dopisać **własne reguły platformy ML** jako ValidatingAdmissionPolicy: zasoby obowiązkowe, zakaz `:latest`, limit czasu Jobów.

## Kroki

### 1. Co by się stało przy `restricted`? (dry-run po stronie serwera — nic nie psuje)

▶️ **Wklej do terminala:**
```sh
kubectl label --dry-run=server --overwrite ns ml pod-security.kubernetes.io/enforce=restricted
# Warning: existing pods in namespace "ml" violate the new PodSecurity enforce level ...
```

### 2. Utwardzenie inference

▶️ **Wklej do terminala:**
```sh
kubectl patch deploy inference --type=strategic --patch-file 03-advanced/07-security-psa-vap/hardened-inference-patch.yaml
kubectl rollout status deploy/inference
kubectl exec deploy/inference -c server -- sh -c 'id; touch /x' # uid=10001, Read-only file system
```

### 3. PSA w trybie ostrzegania i audytu (nie blokuje), potem enforce

▶️ **Wklej do terminala:**
```sh
kubectl label ns ml pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/audit=restricted --overwrite
kubectl rollout restart sts/feature-store        # Warning: ... (Redis jako root, brak seccomp)
```

#### ✍️ Zadanie A: utwardź Redisa, CronJob i Joby

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `03-advanced/07-security-psa-vap/hardened-inference-patch.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a07/feature-store-patch.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a07/feature-pipeline-patch.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a07 && cp 03-advanced/07-security-psa-vap/hardened-inference-patch.yaml $WORK/a07/feature-store-patch.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A07` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na wzór `03-advanced/07-security-psa-vap/hardened-inference-patch.yaml` napisz patche w `$WORK/a07/` i utwardź `feature-store` (Redis: `runAsUser: 999`, `fsGroup: 999`, seccomp, drop ALL), CronJob `feature-pipeline` i Joby. Gdy dry-run z kroku 1 nie zwraca ostrzeżeń → `enforce=restricted`.
- Dry-run ostrzega też o **zakończonych** Podach starych Jobów — usuń je (`kubectl delete jobs --all`).
- Po `enforce` Job `train-v1` z I02 zostanie odrzucony (`violates PodSecurity "restricted:latest"` w zdarzeniach Joba) — od teraz trenuj wersją utwardzoną.

Patch-file to też YAML — przenośny i wersjonowalny.

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
kubectl patch sts feature-store --type=strategic --patch-file $WORK/a07/feature-store-patch.yaml
kubectl patch cronjob feature-pipeline --type=strategic --patch-file $WORK/a07/feature-pipeline-patch.yaml
kubectl delete jobs --all
kubectl label --dry-run=server --overwrite ns ml pod-security.kubernetes.io/enforce=restricted   # bez ostrzeżeń?
kubectl label --overwrite ns ml pod-security.kubernetes.io/enforce=restricted
./setup/check.sh A07
```

<details><summary>Rozwiązanie</summary>

`03-advanced/07-security-psa-vap/solution/feature-store-patch.yaml`
`03-advanced/07-security-psa-vap/solution/feature-pipeline-patch.yaml`
`03-advanced/07-security-psa-vap/solution/train-job-restricted.yaml`
</details>

### 4. Guardrails ML

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/07-security-psa-vap/vap-ml-guardrails.yaml
kubectl label ns ml policy.fti/guardrails=enabled
kubectl create deployment bad --image=fti-lab:latest               # Deny: requests / :latest
kubectl create job adhoc --image=fti-lab:0.1 -- python -m fti.train # Deny: activeDeadlineSeconds
kubectl create job f-check --from=cronjob/feature-pipeline          # ? (sprawdź jobTemplate z I02)
```

#### ✍️ Zadanie B: CronJob zgodny z guardrails

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📝 **Twój plik** (masz go z zadania A — zmieniasz): `$WORK/a07/feature-pipeline-patch.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A07` · rozwiązanie zwinięte na końcu

**Co zrobić:** Popraw CronJob `feature-pipeline` tak, by generowane Joby przechodziły polityki (`kubectl create job --from=cronjob/feature-pipeline x --dry-run=server` bez błędu).

<details><summary>Rozwiązanie</summary>

`activeDeadlineSeconds w 03-advanced/07-security-psa-vap/solution/feature-pipeline-patch.yaml`
</details>

### 5. EXTRA: wdrażanie polityki bez blokowania

`validationActions: ["Warn", "Audit"]` zamiast `Deny` — jak wdrożyć nową politykę na żywym klastrze bez psucia zespołom pracy?

## Pytania
1. Dlaczego `readOnlyRootFilesystem` jest ważne dla serwera modelu (podmiana wag, zatrucie modelu)?
2. Kiedy VAP (CEL, wbudowane) a kiedy Kyverno/OPA Gatekeeper (mutacje, generowanie, raporty)?
3. Sekrety: HF token / klucze do S3 — Secret K8s vs Vault (CSI / injector) vs External Secrets Operator.
4. Supply chain modeli: podpisywanie obrazów (cosign) i weryfikacja przy admission — po co, skoro mamy zakaz `:latest`?

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- PSA `restricted` i guardrails VAP na `ml` → capstone ich wymaga. Skutek: każdy kolejny manifest w `ml` musi być utwardzony i mieć requests/limity (np. `train-bad.yaml` w A08 już jest)
- wyłączenie: `kubectl label ns ml pod-security.kubernetes.io/enforce- policy.fti/guardrails-`
