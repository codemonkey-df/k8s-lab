# A01 — Scheduling: pule GPU, priorytety, wywłaszczanie, drain

**Czas:** ~75 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/01-scheduling-gpu-pools/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Zbudować typowy układ klastra ML: **pula CPU** (wszystko) i **pula GPU** (tylko to, co jawnie tego chce), z priorytetami *inference > trening* i bezpiecznym serwisem węzłów.

| Mechanizm | Pytanie, na które odpowiada |
|---|---|
| taint `nvidia.com/gpu:NoSchedule` | kto **nie może** wejść na węzeł GPU? (wszyscy bez toleration) |
| toleration | kto **może** (ale nie musi) |
| nodeAffinity / nodeSelector | kto **musi** trafić na dany węzeł |
| topologySpreadConstraints / podAntiAffinity | jak rozłożyć repliki (HA inference) |
| PriorityClass | kto ustępuje, gdy brakuje zasobów |
| PDB | ile replik musi przetrwać `drain` / upgrade węzła |

## Kroki

### 1. Pule

▶️ **Wklej do terminala:**
```sh
kubectl label node mlops-worker  pool=cpu
kubectl label node mlops-worker2 pool=gpu
kubectl taint node mlops-worker2 nvidia.com/gpu=present:NoSchedule
kubectl get nodes -L pool ; kubectl describe node mlops-worker2 | grep Taints
```

### 2. Zwykły Pod nie wejdzie na pulę GPU; trening z toleration + affinity — musi

▶️ **Wklej do terminala:**
```sh
kubectl run probe --image=busybox:1.36 --overrides='{"spec":{"nodeSelector":{"pool":"gpu"}}}' -- sleep 3600
kubectl describe pod probe | tail -3      # untolerated taint {nvidia.com/gpu: present}
kubectl delete pod probe
kubectl apply -f 03-advanced/01-scheduling-gpu-pools/priorityclasses.yaml -f 03-advanced/01-scheduling-gpu-pools/train-on-gpu-pool.yaml
kubectl get pod -l job-name=train-gpu-pool -o wide   # NODE = mlops-worker2
```

### 3. Wywłaszczanie — wypełnij pulę GPU treningiem, potem wpuść inference

▶️ **Wklej do terminala:**
```sh
kubectl describe node mlops-worker2 | grep -A6 Allocatable       # ile CPU? dopasuj replicas w 03-advanced/01-scheduling-gpu-pools/batch-fill.yaml
# węzeł kind widzi wszystkie CPU hosta: np. przy 32 CPU -> kubectl scale deploy training-fill --replicas=9 (9 x 3.5 CPU)
kubectl apply -f 03-advanced/01-scheduling-gpu-pools/batch-fill.yaml ; kubectl get pods -l app=training-fill -o wide
kubectl apply -f 03-advanced/01-scheduling-gpu-pools/inference-spread.yaml
kubectl get pods -o wide -w        # część training-fill -> Terminating/Pending (preempted)
kubectl get events --field-selector reason=Preempted
```

### 4. Rozkład replik

`kubectl get pods -l app=inference-ha -o wide` — 2 + 2 na workerach (TSC `maxSkew: 1`).
Eksperyment: usuń `nodeTaintsPolicy: Honor` → 3 repliki `Pending` z `didn't match pod topology spread constraints`. Dlaczego? (control-plane jako pusta domena — tak wyszło przy teście laba)

### 5. Serwis węzła z PDB

▶️ **Wklej do terminala:**
```sh
kubectl get pdb inference-ha
kubectl drain mlops-worker --ignore-daemonsets --delete-emptydir-data
#  "Cannot evict pod as it would violate the pod's disruption budget" -> drain czeka
kubectl uncordon mlops-worker
```

## ✍️ Zadanie

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `03-advanced/01-scheduling-gpu-pools/inference-spread.yaml`
> - 📝 **Twój plik** (kopia przykładu — zmieniasz): `$WORK/a01/inference-prefer-cpu.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a01 && cp 03-advanced/01-scheduling-gpu-pools/inference-spread.yaml $WORK/a01/inference-prefer-cpu.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A01` · rozwiązanie zwinięte na końcu

**Co zrobić:** Skopiuj `03-advanced/01-scheduling-gpu-pools/inference-spread.yaml` jako `$WORK/a01/inference-prefer-cpu.yaml` i zmień tak, by inference **preferował** pulę CPU (`preferredDuringScheduling...` z wagą), a na GPU schodził tylko, gdy CPU się skończy. Sprawdź przy 4 i przy 18 replikach (`replicas` w pliku → `kubectl apply -f`) i `./setup/check.sh A01`. Zwróć uwagę, co trzeba zrobić z TSC. Dlaczego dla małego modelu sklearn to dobra polityka, a dla LLM odwrotnie?

<details><summary>Rozwiązanie</summary>

`03-advanced/01-scheduling-gpu-pools/solution/inference-prefer-cpu.yaml`
</details>

## Pytania
1. Dlaczego sam taint nie wystarczy, żeby trening trafił na GPU, a sama affinity nie wystarczy, żeby inni tam nie weszli?
2. `preemptionPolicy: Never` — co to daje dla Jobów treningowych?
3. Inference z PDB `minAvailable: 3` i 3 replikami — co się stanie przy upgrade węzła? Jak ustawić PDB rozsądnie?

## Sprzątanie

**Usuń** — obciążenie i workloady demo: `training-fill` zajmuje ~30 CPU puli GPU, a PDB `inference-ha` (minAvailable 3) blokowałby każdy `drain`:

▶️ **Wklej do terminala:**
```sh
kubectl delete -f 03-advanced/01-scheduling-gpu-pools/batch-fill.yaml -f 03-advanced/01-scheduling-gpu-pools/inference-spread.yaml -f 03-advanced/01-scheduling-gpu-pools/train-on-gpu-pool.yaml --ignore-not-found
kubectl delete -f $WORK/a01/inference-prefer-cpu.yaml --ignore-not-found
```

**Zostaw:**
- etykiety `pool=cpu/gpu` i taint `nvidia.com/gpu` na `mlops-worker2` → A03 (fake GPU na tej puli); taint zdejmujesz w sprzątaniu A03
- PriorityClasses `inference-critical`, `training-batch` → A03, A10
