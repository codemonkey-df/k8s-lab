# B01 — Klaster kind, kubectl, namespace

**Czas:** ~30 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `01-basic/01-cluster-kubectl/` — polecenia uruchamiasz z root repo (`k8s-lab/`)

## Cel
Postawić własny klaster labowy, poruszać się po nim `kubectl` i przygotować namespace `ml`, w którym będzie żyła cała aplikacja FTI.

## Dlaczego to ważne dla MLOps
Każdy zespół ML dostaje „swój kawałek klastra” — zwykle namespace z limitami. Musisz umieć szybko sprawdzić: na jakim jestem klastrze/kontekście, co tu działa, gdzie wylądował mój Pod.

## Kroki

### 1. Klaster (osobny kubeconfig — główny `~/.kube/config` zostaje nietknięty)

▶️ **Wklej do terminala:**
```sh
source setup/env.sh          # KUBECONFIG=~/.kube/kind-mlops.yaml
./setup/up.sh                # najpierw prereq.sh: brakujące kind/kubectl/helm → ~/.local/bin, istniejące zostają
kubectl config current-context   # kind-mlops
kubectl config get-contexts
kubectl cluster-info
```

### 2. Węzły — to kontenery Dockera

▶️ **Wklej do terminala:**
```sh
kubectl get nodes -o wide
kubectl describe node mlops-worker | sed -n '/Capacity/,/Allocatable/p'
docker ps --filter name=mlops
docker exec mlops-worker ls /mnt/shared      # wspólny "storage" z hosta ($LAB_DATA)
```

### 3. Co jest w klastrze od startu

▶️ **Wklej do terminala:**
```sh
kubectl get pods -A -o wide
kubectl api-resources | head -30
kubectl explain pod.spec.containers.resources
```

### 4. Namespace dla FTI i ustawienie go jako domyślnego

▶️ **Wklej do terminala:**
```sh
kubectl create namespace ml
kubectl config set-context --current --namespace=ml
kubectl get pods          # "No resources found in ml namespace."
```

### 5. Generowanie YAML zamiast pisania od zera (będziesz tego używał cały czas)

▶️ **Wklej do terminala:**
```sh
kubectl run tmp --image=nginx --dry-run=client -o yaml
kubectl create deployment tmp --image=nginx --replicas=2 --dry-run=client -o yaml
kubectl create job tmp --image=busybox --dry-run=client -o yaml -- echo hi
```

### ✍️ 6. Ćwiczenie — pierwszy własny manifest

> ✍️ **Zadanie — piszesz / zmieniasz YAML sam**
> - 📄 **Wzór** (tylko czytasz, nie zmieniasz): szkielet z generatora `kubectl create deployment … --dry-run=client -o yaml` (polecenie niżej)
> - 📝 **Twój plik** (nowy — tworzysz generatorem): `$WORK/b01/hello.yaml`
> - ✅ **Sprawdzenie:** `./setup/check.sh B01` · rozwiązanie zwinięte na końcu

**Co zrobić:** Wygeneruj szkielet do pliku i dopisz resztę ręcznie.

▶️ **Uruchom i sprawdź (wklej do terminala):**
```sh
mkdir -p $WORK/b01
kubectl create deployment hello --image=busybox:1.36 --replicas=2 --dry-run=client -o yaml -- sleep infinity > $WORK/b01/hello.yaml
```
W `$WORK/b01/hello.yaml`:
- dopisz etykietę `part-of: fti` w **szablonie Poda** (`spec.template.metadata.labels`, obok `app: hello`),
- dopisz `resources.requests` kontenera: `cpu: 10m`, `memory: 16Mi` (`kubectl explain deployment.spec.template.spec.containers.resources`),
- usuń śmieci generatora: `creationTimestamp: null`, `strategy: {}`, `status: {}`, `resources: {}`.

▶️ **Wklej do terminala:**
```sh
kubectl apply -f $WORK/b01/hello.yaml
kubectl get deploy,pods -l app=hello --show-labels
./setup/check.sh B01
kubectl delete -f $WORK/b01/hello.yaml
```

<details><summary>Rozwiązanie</summary>

`01-basic/01-cluster-kubectl/solution/hello.yaml`
</details>

## Sprawdzenie
- `kubectl config view --minify | grep namespace` → `namespace: ml`
- `grep current-context ~/.kube/config` nadal wskazuje Twój dotychczasowy kontekst.

## Pytania
1. Czym różni się kontekst od klastra i usera w kubeconfig?
2. Które Pody w `kube-system` są control-plane'em, a które działają na każdym węźle (DaemonSet)?
3. Co zrobi `kubectl get pods -v=8`? Do czego może się przydać?

## Sprzątanie

**Usuń:** nic — wszystko z tego laba jest potrzebne dalej.

**Zostaw:**
- klaster `mlops` i namespace `ml` jako domyślny → wszystkie kolejne laby (Deployment `hello` usunąłeś już w ćwiczeniu)
