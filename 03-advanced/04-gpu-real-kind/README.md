# A04 — (opcjonalny) Prawdziwe GPU NVIDIA w kind + vLLM

**Czas:** ~90 min (+ pobieranie obrazów)  
**Opcjonalny:** tylko jeśli masz kartę **NVIDIA** na hoście. **Nie masz GPU → pomiń ten lab** — żaden kolejny lab od niego nie zależy (patrz niżej, co już przećwiczyłeś bez karty).  
**Linki:** [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator), [nvkind](https://github.com/NVIDIA/nvkind)  
**Przetestowano:** ⚪ opcjonalny — zależny od sprzętu, nie przetestowany end-to-end (wymaga sudo do konfiguracji Dockera)  
**Katalog:** `03-advanced/04-gpu-real-kind/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Uruchomić Pod widzący fizyczne GPU, poznać prawdziwy stos (GPU Operator: toolkit, device-plugin, GFD, DCGM), włączyć time-slicing i postawić serwer LLM (vLLM) na GPU.

## Nie masz GPU? Pomiń — to już umiesz
Kubernetesowa strona GPU jest identyczna dla prawdziwej i emulowanej karty (dla schedulera `nvidia.com/gpu` to liczba w `allocatable`):

| Umiejętność | Gdzie (bez karty) |
|---|---|
| `nvidia.com/gpu`, kolejka Podów, multi-GPU, MIG, quota GPU | A03 (fake-gpu-operator), A02 |
| pule GPU: taint/toleration, affinity, priorytety, wywłaszczanie | A01, A03 |
| metryki GPU (`DCGM_FI_DEV_GPU_UTIL`, pamięć) | A08 EXTRA (fake DCGM) |
| serwowanie LLM (OpenAI API), bramka eval, rollback modelu | A10 (Ollama na CPU) |

A04 dokłada tylko to, czego nie da się udawać: prawdziwy stos GPU Operatora (toolkit, runtime, GFD), realne skutki time-slicingu (brak izolacji pamięci) i strojenie vLLM.

## 0. Wymagania — sprawdź, czy możesz
- karta NVIDIA ze sterownikiem na hoście (`nvidia-smi` działa) — do vLLM z modelem 1.5B wystarczy ~8 GB VRAM,
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (`nvidia-ctk`) i **sudo** (zmiana konfiguracji Dockera),
- ~20 GB wolnego dysku (obraz vLLM ~10 GB + model).

▶️ **Wklej do terminala:**
```sh
nvidia-smi -L                                   # GPU 0: NVIDIA <Twoja karta>
nvidia-ctk --version
docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu24.04 nvidia-smi -L   # GPU widoczne w kontenerze?
```
Któreś polecenie nie działa → najpierw sterownik / toolkit, albo pomiń lab.

> **Docker w kontenerze LXC (np. Proxmox):** toolkit ma tam zwykle `no-cgroups = true` i `docker run --gpus all` kończy się `Failed to initialize NVML: Unknown Error`. Pomaga jawne `--device /dev/nvidia0 --device /dev/nvidiactl --device /dev/nvidia-uvm`. Węzła kind (kontener `--privileged`) to nie dotyczy.

## Kroki

### 1. Docker na hoście (jednorazowo, sudo)

▶️ **Wklej do terminala:**
```sh
sudo nvidia-ctk runtime configure --runtime=docker --set-as-default
sudo nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place
sudo systemctl restart docker
docker info | grep -i 'default runtime'      # nvidia
```
⚠️ Restart Dockera zatrzyma działające kontenery (w tym klaster `mlops` — po restarcie wstanie sam lub `docker start mlops-control-plane mlops-worker mlops-worker2`).

### 2. Osobny klaster GPU (nie mieszamy z fake-gpu)

▶️ **Wklej do terminala:**
```sh
kind create cluster --config 03-advanced/04-gpu-real-kind/kind-gpu.yaml --kubeconfig ~/.kube/kind-mlops-gpu.yaml
export KUBECONFIG=~/.kube/kind-mlops-gpu.yaml
docker exec mlops-gpu-worker ls /dev | grep nvidia          # nvidia0, nvidiactl, nvidia-uvm...
docker exec mlops-gpu-worker ln -sf /sbin/ldconfig /sbin/ldconfig.real   # znany wymóg toolkitu w kind
```

### 3. GPU Operator (sterownik już jest na hoście → `driver.enabled=false`)

▶️ **Wklej do terminala:**
```sh
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia && helm repo update
helm upgrade --install gpu-operator nvidia/gpu-operator --version v26.7.3 -n gpu-operator --create-namespace \
  --set driver.enabled=false --wait --timeout 15m
kubectl -n gpu-operator get pods      # toolkit, device-plugin, gfd, dcgm-exporter, validator
kubectl get node mlops-gpu-worker -o jsonpath='{.status.allocatable}' ; echo
kubectl get node mlops-gpu-worker --show-labels | tr ',' '\n' | grep nvidia.com/gpu
```

### 4. Pierwszy Pod na GPU

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/04-gpu-real-kind/nvidia-smi.yaml && sleep 20 && kubectl logs nvidia-smi    # nazwa i pamięć Twojej karty
```

### 5. Time-slicing (1 karta → 4 „GPU”)

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/04-gpu-real-kind/time-slicing.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config","default":"any"}}}}'
kubectl get node mlops-gpu-worker -o jsonpath='{.status.allocatable.nvidia\.com/gpu}' ; echo   # 4
```

### 6. LLM na GPU (vLLM, OpenAI API)

▶️ **Wklej do terminala:**
```sh
kubectl apply -f 03-advanced/04-gpu-real-kind/vllm.yaml
kubectl -n llm logs -f deploy/vllm
kubectl -n llm port-forward svc/vllm 8000:80 &
curl -s localhost:8000/v1/models
curl -s localhost:8000/v1/chat/completions -H 'content-type: application/json' \
  -d '{"model":"qwen","messages":[{"role":"user","content":"Czym jest Kubernetes? Jedno zdanie."}]}'
curl -s localhost:8000/metrics | grep -E 'vllm:(num_requests|gpu_cache)'
```
W drugim terminalu: `watch -n1 nvidia-smi` na hoście — zajęte ~80% pamięci karty (`--gpu-memory-utilization=0.80`). Mało VRAM (< 8 GB)? Obniż `--max-model-len` albo weź `Qwen/Qwen2.5-0.5B-Instruct`.

## ✍️ Zadanie

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): `03-advanced/04-gpu-real-kind/vllm.yaml`
> - 📝 **Twój plik** (nowy — tworzysz (drugi Deployment vLLM)): `$WORK/a04/vllm-2.yaml`
> - ▶️ **Start:** `mkdir -p $WORK/a04 && cp 03-advanced/04-gpu-real-kind/vllm.yaml $WORK/a04/vllm-2.yaml`

**Co zrobić:** Przy time-slicingu `replicas: 4` uruchom **dwa** Deploymenty vLLM po `nvidia.com/gpu: 1` z `--gpu-memory-utilization=0.80`. Co się stanie i dlaczego? Jak ustawić parametry, żeby się zmieściły? (Wniosek: time-slicing nie izoluje pamięci.)

## Pytania
1. Które komponenty GPU Operatora robią to, co w A03 tylko „udawał” fake-gpu-operator?
2. Dlaczego `strategy: Recreate` dla vLLM na jednym GPU?
3. Jakie metryki vLLM nadają się do autoskalowania (I06, pytanie 2)?
4. Jak przyspieszyć start (obraz 10 GB + wagi)? (pre-pull/DaemonSet, Spegel, PVC z cache, model jako OCI/ImageVolume)

## Sprzątanie

**Usuń** — osobny klaster GPU — trzyma kartę i RAM; klastra `mlops` nie dotyka:

▶️ **Wklej do terminala:**
```sh
kind delete cluster --name mlops-gpu --kubeconfig ~/.kube/kind-mlops-gpu.yaml
source ./setup/env.sh     # KUBECONFIG z powrotem na klaster mlops
```

**Zostaw:**
- konfiguracja Dockera z kroku 1 — nie przeszkadza `mlops`. Cofnięcie (opcjonalne, sudo): w `/etc/docker/daemon.json` usuń `"default-runtime": "nvidia"`, w `/etc/nvidia-container-runtime/config.toml` ustaw `accept-nvidia-visible-devices-as-volume-mounts = false`, `sudo systemctl restart docker`
