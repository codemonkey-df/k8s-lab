# A09 — Troubleshooting: 8 zepsutych workloadów ML + `kubectl debug`

**Czas:** ~60 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `03-advanced/09-troubleshooting/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Wyrobić odruch diagnozy: **objaw → gdzie patrzeć → przyczyna**. To najczęstsza praca admina platformy ML („mój trening wisi w Pending”, „model nie odpowiada”).

## Narzędzia

▶️ **Wklej do terminala:**
```sh
kubectl get pods -o wide                   # STATUS, RESTARTS, NODE
kubectl describe pod <p>                   # Events na dole!
kubectl logs <p> [-c kontener] [--previous]
kubectl get events --sort-by=.lastTimestamp -n debug
kubectl get endpointslices -l kubernetes.io/service-name=<svc>
kubectl debug -it <pod> --image=nicolaka/netshoot --target=server   # ephemeral container (wspólny PID ns)
kubectl debug <pod> -it --copy-to=<pod>-dbg --container=server -- sh # kopia z innym poleceniem
kubectl debug node/mlops-worker -it --image=busybox:1.36            # shell na węźle (/host)
```

## Kroki

▶️ **Wklej do terminala:**
```sh
kubectl create ns debug
kubectl apply -f 03-advanced/09-troubleshooting/broken/
kubectl get all,pvc -n debug
```
Dla każdego `03-advanced/09-troubleshooting/broken/0X.yaml` zapisz: objaw, komendę, która pokazała przyczynę, poprawkę. Napraw i sprawdź. Nie czytaj manifestu, zanim nie zobaczysz objawu w `kubectl`.

`kubectl debug` w praktyce (na naprawionym `broken-04`):

▶️ **Wklej do terminala:**
```sh
P=$(kubectl -n debug get pod -l app=broken-04 -o name | head -1)
kubectl -n debug debug -it $P --image=nicolaka/netshoot --target=server -- sh
#   ss -ltn ; curl -s localhost:8080/ready ; nslookup broken-05 ; ps aux
kubectl -n debug debug $P -it --copy-to=dbg-copy --container=server -- sh    # kopia Poda z innym poleceniem
kubectl -n debug debug node/mlops-worker -it --image=busybox:1.36 -- chroot /host crictl ps
```
Namespace z PSA `restricted` (np. `ml` po A07):
- netshoot (root) jest **odrzucany**: `violates PodSecurity "restricted:latest"` — to dobrze, inaczej każdy z `pods/ephemeralcontainers` obszedłby politykę,
- działa `--profile=restricted` + obraz nie-root:
  `kubectl -n ml debug <pod> --image=fti-lab:0.1 --target=server --profile=restricted -- python -c "import urllib.request;print(urllib.request.urlopen('http://localhost:8080/ready').read())"`,
- `kubectl debug node/...` tworzy uprzywilejowany Pod w **bieżącym** namespace — w `ml` nie przejdzie, dlatego wyżej `-n debug`.

Postęp: `./setup/check.sh A09` (✅ dla każdego naprawionego workloadu).

<details><summary>Rozwiązania</summary>

`03-advanced/09-troubleshooting/solution/SOLUTIONS.md`, sprawdzone naprawy wszystkich 8: `./03-advanced/09-troubleshooting/solution/fix-all.sh`
</details>

## Pytania
1. `Pending` vs `ContainerCreating` vs `Init:0/1` vs `Running 0/1` — który etap zawodzi w każdym przypadku i kto za niego odpowiada (scheduler / kubelet+CSI / init / aplikacja)?
2. Kiedy `--previous` jest niezbędne?
3. Dlaczego ephemeral container zamiast „dorzucenia curla do obrazu modelu”?

## Sprzątanie

**Usuń** — namespace z zepsutymi workloadami. **Koniecznie przed A10**: goły Pod `broken-07` (bez kontrolera) blokuje `kubectl drain` — `cannot delete Pods that declare no controller` (sprawdzone przy teście):

▶️ **Wklej do terminala:**
```sh
kubectl delete ns debug
```

**Zostaw:**
- nic z tego laba nie jest potrzebne dalej
