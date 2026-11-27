# A03 — GPU bez GPU: fake-gpu-operator (scheduling, multi-GPU, MIG)

**Czas:** ~60 min  
**Linki:** [fake-gpu-operator](https://github.com/run-ai/fake-gpu-operator)  
**Wymaga:** A01 (etykieta `pool=gpu` + taint na `mlops-worker2`, PriorityClass `training-batch`).  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0), fake-gpu-operator 0.2.1  
**Katalog:** `03-advanced/03-gpu-fake-operator/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Przećwiczyć całą **kubernetesową** stronę GPU: extended resource `nvidia.com/gpu`, kolejkowanie przy braku kart, multi-GPU, MIG, quota GPU — na emulowanym A100 (4 GPU na `mlops-worker2`).
Prawdziwe obliczenia na GPU → A04.

> Nie instaluj fake-gpu-operatora i prawdziwego GPU Operatora w tym samym klastrze. A04 używa osobnego klastra.

## Kroki

### 1. Instalacja (Helm OCI) i oznaczenie puli

▶️ **Wklej do terminala:**
```sh
kubectl label node mlops-worker2 run.ai/simulated-gpu-node-pool=default nvidia.com/gpu.product=NVIDIA-A100-SXM4-40GB --overwrite
# przetestowane 27.11 na chart 0.2.1; mig-faker ma 0 Podów — MIG łatamy ręcznie w kroku 4
helm upgrade --install gpu-operator oci://ghcr.io/run-ai/fake-gpu-operator/fake-gpu-operator \
  -n gpu-operator --create-namespace -f 03-advanced/03-gpu-fake-operator/topology.yaml
kubectl -n gpu-operator get pods
kubectl -n gpu-operator rollout status ds/device-plugin --timeout=3m
# rejestracja GPU w kubelecie trwa jeszcze ~30-60 s:
until kubectl get node mlops-worker2 -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' | grep -q 4; do sleep 5; done
kubectl get nodes -o custom-columns=NODE:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
```
Device-plugin to **DaemonSet** — dlaczego? Ma tolerancję na nasz taint?
(`kubectl -n gpu-operator get ds -o yaml | grep -A3 tolerations`; jeśli nie — `kubectl -n gpu-operator patch ds ...` albo values chartu.)

### 2. Trening na GPU i kolejka

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/03-gpu-fake-operator/gpu-train-job.yaml
kubectl get pods -l app=gpu-train -o wide       # 4 Running, 2 Pending
kubectl describe pod <pending> | tail -3        # Insufficient nvidia.com/gpu
kubectl describe node mlops-worker2 | grep -A10 'Allocated resources' | grep nvidia
```

### 3. Multi-GPU

▶️ **Wklej do terminala:**
```sh
kubectl delete job gpu-train
kubectl wait --for=delete pod -l app=gpu-train --timeout=90s   # kończące się Pody nadal trzymają GPU!
kubectl apply -f 03-advanced/03-gpu-fake-operator/multi-gpu-pod.yaml             # 4 GPU = cały węzeł
sed 's/name: multi-gpu-train/name: multi-gpu-8/; s/nvidia.com\/gpu: 4/nvidia.com\/gpu: 8/' 03-advanced/03-gpu-fake-operator/multi-gpu-pod.yaml | kubectl apply -f -
kubectl get pods -l workload=training           # multi-gpu-8 Pending na zawsze
kubectl delete pod -l workload=training
```

### 4. MIG

(fake-gpu-operator nie rejestruje `nvidia.com/mig-*` — łatamy capacity ręcznie, w realu robi to GPU Operator):

▶️ **Wklej do terminala:**
```sh
kubectl patch node mlops-worker2 --subresource=status --type=merge \
  -p '{"status":{"capacity":{"nvidia.com/mig-1g.5gb":"7","nvidia.com/mig-3g.20gb":"2"}}}'
kubectl apply -f 03-advanced/03-gpu-fake-operator/mig-pods.yaml
kubectl describe node mlops-worker2 | grep -E 'mig-(1g|3g)'
kubectl delete pod -l mig-demo=true
```

### 5. Quota GPU (A02)

w `team-nlp` uruchom Pod z `nvidia.com/gpu: 3` (+ toleration) → `exceeded quota: compute, requested: requests.nvidia.com/gpu=3, limited: 2`.

## ✍️ Zadanie

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `02-intermediate/02-jobs-fti-pipeline/hpo-indexed-job.yaml`
> - 📝 **Twój plik** (nowy — tworzysz): `$WORK/a03/hpo-gpu.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a03 && cp 02-intermediate/02-jobs-fti-pipeline/hpo-indexed-job.yaml $WORK/a03/hpo-gpu.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh A03` · rozwiązanie zwinięte na końcu

**Co zrobić:** Sweep HPO z I02 przerób na wersję GPU (`$WORK/a03/hpo-gpu.yaml`, Job `hpo-gpu`, 5 triali): każdy trial `nvidia.com/gpu: 1`, `parallelism: 5`, pula GPU (toleration + affinity), `priorityClassName: training-batch`. Ile triali biegnie naraz? Co by zmienił **time-slicing** z `replicas: 4`? Sprawdź: `./setup/check.sh A03`.

<details><summary>Rozwiązanie</summary>

`03-advanced/03-gpu-fake-operator/solution/hpo-gpu.yaml`
</details>

## Time-slicing vs MIG vs MPS
| | Izolacja pamięci | Sprzęt | Kiedy |
|---|---|---|---|
| Time-slicing | brak (wszyscy widzą całą pamięć) | każda karta NVIDIA | dev, notebooki, małe inference |
| MIG | sprzętowa | A100/A30/H100/H200 | produkcyjne inference multi-tenant |
| MPS | częściowa | CUDA | wiele małych procesów compute-bound |

## Pytania
1. Dlaczego dla `nvidia.com/gpu` requests == limits i nie ma overcommitu?
2. 4 GPU na jednym węźle vs 4 GPU na różnych — jak to wymusić / czego potrzebuje trening rozproszony (NCCL, PyTorchJob)?
3. Co dodaje do tego **Kueue** (ResourceFlavor → ClusterQueue → LocalQueue, fair sharing, preemption między zespołami)?
4. Na Twoim RTX 4070 Ti SUPER — MIG zadziała? (A04)

## Sprzątanie

**Usuń** — fake GPU i namespace zespołu. **Taint koniecznie**: bez operatora `mlops-worker2` dalej odpycha zwykłe Pody, więc inference (HPA), Redis i kolejne laby mieszczą się tylko na jednym workerze:

▶️ **Wklej do terminala:**
```sh
kubectl delete job hpo-gpu --ignore-not-found
helm uninstall gpu-operator -n gpu-operator ; kubectl delete ns gpu-operator
kubectl taint node mlops-worker2 nvidia.com/gpu-
kubectl delete ns team-nlp
```

**Zostaw:**
- etykiety `pool=cpu/gpu` — nie przeszkadzają (A10: pula dla Ollamy)
- fake GPU zainstalujesz ponownie tylko do EXTRA w A08 (metryki DCGM)
