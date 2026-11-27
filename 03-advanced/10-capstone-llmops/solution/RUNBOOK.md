# RUNBOOK — platforma FTI + LLM (A10)

Zawsze zaczynaj od tego samego:
```sh
kubectl -n ml get pods,events --sort-by=.lastTimestamp | tail -20
kubectl -n ml describe pod <pod> | sed -n '/Events/,$p'
kubectl -n ml logs <pod> -c <kontener> --previous     # poprzedni (crashujący) start
```

| # | Objaw | Rozpoznanie | Naprawa |
|---|-------|-------------|---------|
| 1 | Brak nowych Podów, Deployment/Job „stoi” (`READY 0/2`, Job bez Podów) | Pod **w ogóle nie powstał** → zdarzenia kontrolera, nie Poda: `kubectl -n ml get events --field-selector reason=FailedCreate` → `violates PodSecurity "restricted"`, `exceeded quota: compute`, `denied request` (VAP) | brakujący `securityContext` (A07), requests/limits (VAP), `activeDeadlineSeconds`/`ttl` w Jobie, za mała quota (`describe quota compute`). Szablon Joba: `solution/train-job.yaml` |
| 2 | `ImagePullBackOff` / `ErrImageNeverPull` | `describe pod` → `Failed to pull image` — tag, którego nie ma w kind, albo `:latest` z `Always` | `./app/build.sh <tag>` (kind load), tag jawny, `imagePullPolicy: IfNotPresent` |
| 3 | `Init:CrashLoopBackOff` w inference albo nowa wersja „nie wchodzi” | `logs <pod> -c fetch-model` → `brak modelu /registry/vN` lub `UWAGA ... model wypalony w obrazie` | model nie przeszedł bramki albo zła wersja w `release.env` → `./train.sh vN`, potem `./release.sh vN`; rollback: `kubectl -n ml rollout undo deploy/inference` **i** poprawienie `release.env` (inaczej następny `apply -k` wróci do złej wersji) |
| 4 | 503 / `no healthy upstream` przez Gateway, Pody `Running` | `kubectl -n ml get endpointslices -l kubernetes.io/service-name=inference` puste → selektor Service ≠ etykiety Podów (np. brak `track: stable`) lub readiness nie przechodzi; Pody gotowe, a dalej timeout → NetworkPolicy | etykiety/selektor; `curl` z Poda w `ml` (`kubectl debug --profile=restricted`, A09); netpol `inference-ingress` musi wpuszczać `envoy-gateway-system` |
| 5 | `OOMKilled` (trening), `CrashLoopBackOff` po kilkudziesięciu sekundach (serwer) | `describe pod` → `Last State: Terminated, Reason: OOMKilled`; dla serwera `Liveness probe failed` przed `/ready` | trening: `limits.memory` (i quota `limits.memory`); serwer: `startupProbe` dłuższa niż ładowanie modelu, liveness na `/healthz`, nie na `/ready` |
| 6 | PVC `Pending` | `describe pvc` → `storageclass "..." not found` / `waiting for first consumer` (to drugie jest OK do startu Poda) | istniejąca StorageClass (`standard`); PVC jest niezmienny → usuń i utwórz ponownie |
| 7 | LLM: `504 upstream request timeout` po 15 s | Envoy ma domyślny timeout żądania 15 s | `timeouts.request` w HTTPRoute (`solution/llm/ollama.yaml`: 300 s) |
| 8 | LLM: odpowiedzi wolne jak 0,3 tok/s, CPU 100% | `ollama` liczy wątki z rdzeni hosta, nie z limitu; `kubectl top pod -n llm` | `PARAMETER num_thread` w aliasie `llm` (`llm-config.NUM_THREAD`), requests.cpu = wątki, bez limitu CPU |
| 9 | Alert `FeaturesStale` | `kubectl -n ml get cronjob feature-pipeline` (`SUSPEND`, `LAST SCHEDULE`), logi ostatniego Joba | `suspend: false`; ręcznie: `kubectl -n ml create job f-now --from=cronjob/feature-pipeline` |
| 10 | `kubectl drain` wisi | `cannot delete Pods that declare no controller` albo PDB `Cannot evict pod as it would violate the pod's disruption budget` | gołe Pody usuń ręcznie; PDB: dołóż repliki / poczekaj, aż nowa replika będzie Ready. Uwaga: Redis (RWO local-path) wróci dopiero po `uncordon` węzła |
