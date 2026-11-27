# I09 — Helm: paczka z serwerem modelu

**Czas:** ~75 min  
**Przetestowano:** ✅ 2026-11-27 (kind v0.33.0, Kubernetes v1.37.0)  
**Katalog:** `02-intermediate/09-helm/` — polecenia uruchamiasz z korzenia repo (`k8s-lab/`)

## Cel
Umieć (A) zainstalować i obsłużyć cudzy chart (tak instaluje się 90% narzędzi ML: Prometheus, KubeRay, GPU Operator, Kueue, vLLM stack) i (B) zapakować własny serwer modelu w chart z wartościami per środowisko.

## Część A — cudzy chart (Helm v4)
Ćwiczymy na publicznym chartcie demo [podinfo](https://github.com/stefanprodan/podinfo) z rejestru OCI:

▶️ **Wklej do terminala:**
```sh
helm show values oci://ghcr.io/stefanprodan/charts/podinfo | head -30
helm upgrade --install hello oci://ghcr.io/stefanprodan/charts/podinfo -n helm-demo --create-namespace --wait
helm ls -n helm-demo ; helm get values hello -n helm-demo
helm upgrade hello oci://ghcr.io/stefanprodan/charts/podinfo -n helm-demo --set replicaCount=2 --wait
kubectl -n helm-demo get pods
helm history hello -n helm-demo ; helm rollback hello 1 -n helm-demo
helm uninstall hello -n helm-demo
```
> Helm 4: `--atomic` z Helma 3 to teraz `--rollback-on-failure` (sprawdź `helm upgrade --help`).

## Część B — ✍️ własny chart `fti-inference`
Szablony piszesz na bazie manifestów z poprzednich labów (`$WORK/inference.yaml`, `01-basic/04-service/service.yaml`, HTTPRoute z I05, HPA z I06, CronJob z I02).

▶️ **Wklej do terminala:**
```sh
mkdir -p $WORK/09-helm
helm create $WORK/09-helm/fti-inference        # szkielet, potem przytnij do potrzeb
```
Wymagane wartości (`values.yaml`):
- `replicaCount`, `image.registry` (opcjonalny, bez `/`), `image.repository`, `image.tag` (domyślnie `appVersion`),
- `model.version` + `model.registryClaim` (initContainer z I03; puste → model z obrazu),
- `config` (mapa → ConfigMap), `resources`,
- `gateway.enabled/host` → HTTPRoute, `autoscaling.enabled` → HPA,
- `gpu.count` > 0 → `limits.nvidia.com/gpu` + toleration (przyda się w A03/A04),
- `featureCronjobs` — mapa nazwa→harmonogram, CronJoby generowane `range`, domyślny harmonogram `"*/5 * * * *"` gdy pusty,
- adnotacja `checksum/config` (rollout po zmianie ConfigMap), `NOTES.txt`.

Testowanie bez klastra i z klastrem:

▶️ **Wklej do terminala:**
```sh
C=$WORK/09-helm/fti-inference     # Twój chart
helm lint $C
helm template t $C --set gpu.count=1 | less
helm upgrade --install wine $C -n ml --wait
helm upgrade --install wine-prod $C -n ml-prod --create-namespace -f $WORK/09-helm/values-prod.yaml --wait
./setup/check.sh I09
```
Uwaga: `ml-prod` nie ma PVC `model-store` → ustaw `--set model.registryClaim=` albo utwórz PVC (PV `model-store` jest już związany z `ml`!). Dobre pytanie do przemyślenia: jak współdzielić rejestr między namespace'ami? (obiektowy storage, nie PVC).

<details><summary>Rozwiązanie</summary>

`02-intermediate/09-helm/solution/fti-inference/`, `02-intermediate/09-helm/solution/values-prod.yaml`
</details>

## Pytania
1. `helm upgrade --install` vs `helm install` — dlaczego w CI zawsze to pierwsze?
2. Gdzie Helm trzyma stan release'u? (`kubectl get secret -n ml -l owner=helm`)
3. Chart w rejestrze OCI (`helm push oci://...`) — jak to się ma do wersjonowania modelu?

## Sprzątanie

**Usuń** — release'y z laba. **`wine` w `ml` usuń koniecznie**: jego Pody nie mają `securityContext`, więc po A07 (PSA `restricted`) nowe Pody tego release'u byłyby odrzucane, a dry-run w A07 by o nich ostrzegał:

▶️ **Wklej do terminala:**
```sh
helm uninstall wine -n ml
helm uninstall wine-prod -n ml-prod
helm uninstall hello -n helm-demo 2>/dev/null ; kubectl delete ns ml-prod helm-demo --ignore-not-found
```

**Zostaw:**
- Twój chart w `$WORK/09-helm/fti-inference` (pliki, nie obiekty w klastrze)
