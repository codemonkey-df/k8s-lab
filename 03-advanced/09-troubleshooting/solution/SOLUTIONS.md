# Rozwiązania A09 (nie zaglądaj przed diagnozą!)

| # | Objaw | Przyczyna | Jak to zobaczyć | Naprawa |
|---|---|---|---|---|
| 01 | `ErrImagePull` / `ImagePullBackOff` | tag `0.2` nie załadowany do kind, brak `imagePullPolicy` → próba pull z Docker Hub | `describe pod` → Events | `./app/build.sh 0.2` albo tag `0.1` + `IfNotPresent` |
| 02 | `CrashLoopBackOff` | literówka w module: `fti.server` zamiast `fti.serve` | `logs --previous` → `ModuleNotFoundError` / `Could not import module` | poprawić `command` |
| 03 | Job `Pending` na zawsze | `requests.cpu: 64` > Allocatable każdego węzła | `describe pod` → `0/3 nodes are available: Insufficient cpu` | realne requests; dla GPU analogicznie `Insufficient nvidia.com/gpu` |
| 04 | `Running`, ale `READY 0/2` | `MODEL_PATH` wskazuje na brak pliku (brak wolumenu z rejestrem) → `/ready` = 503 | `logs` → `brak modelu`; `describe` → `Readiness probe failed: 503` | dodać wolumen `model-store`/initContainer (I03) |
| 05 | Service nie odpowiada | selektor `tier: models` ≠ etykieta `tier: model` **i** `targetPort: 8000` ≠ 8080 | `get endpointslices -l kubernetes.io/service-name=broken-05` → puste | poprawić selektor i `targetPort: http` |
| 06 | Job `Failed`, `OOMKilled` | 3000 drzew w 96Mi | `describe pod` → `Last State: Terminated, Reason: OOMKilled, Exit Code: 137` | więcej pamięci albo mniejszy model; `podFailurePolicy` może ignorować/ponawiać 137 |
| 07 | PVC i Pod `Pending` | StorageClass `fast-nvme` nie istnieje | `describe pvc` → `storageclass.storage.k8s.io "fast-nvme" not found` | `storageClassName: standard` (lub pominąć) |
| 08 | Restarty w pętli, nigdy Ready | liveness na `/ready` z małym progiem, a model ładuje się 30 s → kubelet zabija kontener w trakcie ładowania | `describe` → `Liveness probe failed ... will be restarted`, rosnące `RESTARTS` | `startupProbe` + liveness na `/healthz` (B05) |
