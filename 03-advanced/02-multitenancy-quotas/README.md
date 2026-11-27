# A02 — Multi-tenancy: namespace zespołu, ResourceQuota, LimitRange

**Czas:** ~40 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/02-multitenancy-quotas/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Jako admin platformy ML dać zespołowi namespace z budżetem: CPU/RAM, **GPU**, storage, liczba Jobów, zakaz NodePortów — i domyślnymi zasobami dla „zapominalskich”.

## Kroki

### 1. Namespace zespołu z quotą

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/02-multitenancy-quotas/team-namespace.yaml
kubectl describe quota -n team-nlp
kubectl describe limitrange -n team-nlp
```

### 2. LimitRange w akcji — Pod bez `resources` dostaje domyślne

▶️ **Wklej do terminala:**
```sh
kubectl -n team-nlp run nb --image=fti-lab:0.1 --image-pull-policy=IfNotPresent -- sleep infinity
kubectl -n team-nlp get pod nb -o jsonpath='{.spec.containers[0].resources}{"\n"}'
```

### 3. Przekroczenie budżetu

▶️ **Wklej do terminala:**
```sh
kubectl -n team-nlp create deployment big --image=busybox:1.36 --replicas=10 -- sleep infinity
kubectl -n team-nlp set resources deploy/big --requests=cpu=1
kubectl -n team-nlp get rs -l app=big          # rollout utknął: stary RS (100m z LimitRange) + nowy (1 CPU)
kubectl -n team-nlp describe quota compute      # requests.cpu ~3600m / 4
kubectl -n team-nlp get events --field-selector reason=FailedCreate | tail -2   # exceeded quota: compute
kubectl -n team-nlp expose deploy big --port=80 --type=NodePort   # Forbidden: services.nodeports
kubectl -n team-nlp delete deploy big
```

### ✍️ 4. Zadanie: sweep w budżecie zespołu

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/02-jobs-fti-pipeline/hpo-indexed-job.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a02/hpo-team-nlp.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a02 && cp 02-intermediate/02-jobs-fti-pipeline/hpo-indexed-job.yaml $WORK/a02/hpo-team-nlp.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A02` · rozwiązanie zwinięte na końcu

**Co zrobić:** Na bazie `02-intermediate/02-jobs-fti-pipeline/hpo-indexed-job.yaml` napisz `$WORK/a02/hpo-team-nlp.yaml` — Indexed Job `hpo-team-nlp` w `team-nlp` (jak w I02, ale bez PVC — `team-nlp` nie ma `features`, trial liczy cechy w pamięci) z `completions: 8`, `parallelism: 8`, każdy trial `requests.cpu: 1`. Ile Podów pracuje naraz i dlaczego? Gdzie widać odmowy? Czy Job i tak się kończy? Sprawdź: `./setup/check.sh A02`.

<details><summary>Rozwiązanie</summary>

`03-advanced/02-multitenancy-quotas/solution/hpo-team-nlp.yaml`
</details>

### 5. Quota GPU sprawdzisz po A03

Pod z `nvidia.com/gpu: 3` w `team-nlp` → `exceeded quota`.

## Pytania
1. Różnica między ResourceQuota a LimitRange — kto pilnuje sumy, a kto pojedynczego kontenera?
2. Quota „twarda” vs kolejkowanie: dlaczego dla Jobów treningowych lepszy jest **Kueue** (Job czeka w kolejce, zamiast dostać odmowę i zniknąć)?
3. Jak dać zespołowi dostęp tylko do jego namespace? (I07: RoleBinding do `edit` w `team-nlp`)

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- namespace `team-nlp` → A03 krok 5 (quota GPU). Usuwasz go w sprzątaniu A03
