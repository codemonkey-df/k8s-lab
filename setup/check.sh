#!/usr/bin/env bash
# Sprawdza wynik ćwiczeń laba w klastrze:  ./setup/check.sh B03   (lista: ./setup/check.sh)
# Sprawdzany jest STAN KLASTRA (to, co zaaplikowałeś), nie pliki — nazwy obiektów jak w treści ćwiczenia.
source "$(dirname "$0")/env.sh" >/dev/null
LAB=$(dirname "$0")/..
PASS=0; FAIL=0
K="kubectl -n ml"

ok()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then echo "  ✅ $d"; PASS=$((PASS+1)); else echo "  ❌ $d"; FAIL=$((FAIL+1)); fi; }
no()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then echo "  ❌ $d"; FAIL=$((FAIL+1)); else echo "  ✅ $d"; PASS=$((PASS+1)); fi; }
# get <ns> <obiekt> <jsonpath>
get() { kubectl -n "$1" get "$2" -o jsonpath="$3" 2>/dev/null; }
eq()  { [ "$(get "$1" "$2" "$3")" = "$4" ]; }            # eq ns obiekt jsonpath wartość
has() { get "$1" "$2" "$3" | grep -q -- "$4"; }          # has ns obiekt jsonpath fragment
applied() { get "$1" "$2" '{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}' | grep -q -- "$3"; }
http() { [ "$(curl -s -m5 -o /dev/null -w '%{http_code}' "${@:2}")" = "$1" ]; }   # http 200 <curl args>
ready_eps() { kubectl -n "$1" get endpointslices -l kubernetes.io/service-name="$2" \
                -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' | grep -c .; }
can() { [ "$(kubectl auth can-i "$@" -n ml --as=system:serviceaccount:ml:data-scientist)" = yes ]; }
export K
export -f get eq has applied http ready_eps can
PRED='{"instances":[[13.2,1.8,2.1,16,100,2.4,2.6,0.3,1.9,5.6,1.0,3.2,1100]]}'; export PRED

case "${1:-}" in
B01) echo "B01 — Deployment hello z wygenerowanego YAML"
  ok "domyślny namespace kontekstu = ml"          bash -c 'kubectl config view --minify -o jsonpath="{..namespace}" | grep -qx ml'
  ok "deploy/hello utworzony z pliku (apply -f)"  applied ml deploy/hello hello
  ok "2 gotowe repliki"                          eq ml deploy/hello '{.status.readyReplicas}' 2
  ok "obraz busybox:1.36"                        eq ml deploy/hello '{.spec.template.spec.containers[0].image}' busybox:1.36
  ok "etykieta part-of=fti na Podach"            eq ml deploy/hello '{.spec.template.metadata.labels.part-of}' fti
  ok "requests.cpu"                              has ml deploy/hello '{.spec.template.spec.containers[0].resources.requests.cpu}' '[0-9]'
  ok "requests.memory"                           has ml deploy/hello '{.spec.template.spec.containers[0].resources.requests.memory}' '[0-9]' ;;
B03) echo "B03 — Pod train-once"
  ok "Pod train-once zakończony (Succeeded)"     eq ml pod/train-once '{.status.phase}' Succeeded
  ok "restartPolicy: Never"                      eq ml pod/train-once '{.spec.restartPolicy}' Never
  ok "etykiety app=training, part-of=fti"        eq ml pod/train-once '{.metadata.labels.app}/{.metadata.labels.part-of}' training/fti
  ok "w logach jest accuracy"                    bash -c "$K logs train-once | grep -q accuracy" ;;
B04) echo "B04 — Service tylko dla canary"
  ok "Pod inference-canary gotowy, track=canary" eq ml pod/inference-canary '{.metadata.labels.track}/{.status.containerStatuses[0].ready}' canary/true
  ok "Service inference-canary ma 1 endpoint"    bash -c '[ $(ready_eps ml inference-canary) = 1 ]'
  ok "...i jest to IP Poda canary"               bash -c "kubectl -n ml get endpointslices -l kubernetes.io/service-name=inference-canary -o jsonpath='{..addresses[0]}' | grep -qx \$(kubectl -n ml get pod inference-canary -o jsonpath='{.status.podIP}')"
  ok "Service inference ma 2 endpointy (oba Pody)" bash -c '[ $(ready_eps ml inference) = 2 ]'
  ok "targetPort nazwany (http)"                 eq ml svc/inference-canary '{.spec.ports[0].targetPort}' http ;;
B05) echo "B05 — sondy i zasoby slow-model"
  ok "startupProbe ustawiona"                    has ml pod/slow-model '{.spec.containers[0].startupProbe}' httpGet
  ok "readinessProbe na /ready"                  eq ml pod/slow-model '{.spec.containers[0].readinessProbe.httpGet.path}' /ready
  ok "livenessProbe na /healthz"                 eq ml pod/slow-model '{.spec.containers[0].livenessProbe.httpGet.path}' /healthz
  ok "requests cpu+memory, limit memory"         bash -c "kubectl -n ml get pod slow-model -o jsonpath='{.spec.containers[0].resources}' | grep -q '\"limits\":{[^}]*memory' && kubectl -n ml get pod slow-model -o jsonpath='{.spec.containers[0].resources.requests.cpu}' | grep -q ."
  ok "Ready i bez restartów"                     eq ml pod/slow-model '{.status.containerStatuses[0].ready}/{.status.containerStatuses[0].restartCount}' true/0 ;;
B06) echo "B06 — nowa wersja przez YAML"
  ok "MODEL_VERSION=baked-1 zaaplikowane z pliku (nie set env)" applied ml deploy/inference baked-1
  ok "adnotacja change-cause w manifeście"       applied ml deploy/inference change-cause
  ok "rollout history ≥ 2 rewizje"               bash -c "[ \$($K get rs -l app=inference --no-headers | wc -l) -ge 2 ]"
  ok "2 dostępne repliki"                        eq ml deploy/inference '{.status.availableReplicas}' 2 ;;
B07) echo "B07 — ConfigMap i Secret w Deploymencie"
  ok "envFrom: configMapRef inference-config"    has ml deploy/inference '{.spec.template.spec.containers[0].envFrom}' inference-config
  ok "wolumen configMap z serving.json"          has ml deploy/inference '{.spec.template.spec.volumes}' inference-config
  ok "plik /etc/fti/serving.json w Podzie"       $K exec deploy/inference -c server -- cat /etc/fti/serving.json
  ok "HF_TOKEN z secretKeyRef"                   has ml deploy/inference '{.spec.template.spec.containers[0].env}' secretKeyRef
  ok "HF_TOKEN widoczny w kontenerze"            bash -c "$K exec deploy/inference -c server -- printenv HF_TOKEN | grep -q hf_" ;;
I01) echo "I01 — Pod cache-demo"
  ok "Pod cache-demo Running"                    eq ml pod/cache-demo '{.status.phase}' Running
  ok "model-store zamontowany readOnly"          has ml pod/cache-demo '{.spec.volumes[*].persistentVolumeClaim}' '"readOnly":true'
  ok "emptyDir z sizeLimit 200Mi"                has ml pod/cache-demo '{.spec.volumes[*].emptyDir.sizeLimit}' 200Mi
  no "zapis do /models się NIE udaje"            $K exec cache-demo -- touch /models/x
  ok "model skopiowany do /cache"                bash -c "$K exec cache-demo -- find /cache -name model.joblib | grep -q ." ;;
I02) echo "I02 — bramka jakości train-bad"
  ok "Job train-bad zakończony jako Failed"      has ml job/train-bad '{.status.conditions[?(@.status=="True")].type}' Failed
  ok "podFailurePolicy z regułą na exit code"    has ml job/train-bad '{.spec.podFailurePolicy.rules[*].onExitCodes}' 1
  ok "tylko 1 Pod (bez ponawiania)"              bash -c "[ \$($K get pods -l job-name=train-bad --no-headers | wc -l) = 1 ]"
  ok "MIN_ACCURACY=0.99"                         has ml job/train-bad '{.spec.template.spec.containers[0].env}' 0.99 ;;
I03) echo "I03 — rollout modelu v2 z YAML"
  ok "Job train-v2 przeszedł bramkę"             eq ml job/train-v2 '{.status.succeeded}' 1
  ok "MODEL_VERSION v2 zaaplikowane z pliku"     applied ml deploy/inference '"v2"'
  ok "change-cause wspomina v2"                  has ml deploy/inference '{.metadata.annotations.kubernetes\.io/change-cause}' v2
  ok "/version zwraca model v2"                  bash -c "curl -s -m5 localhost:30080/version | grep -q '\"model_version\":\"v2\"'" ;;
I04) echo "I04 — feature store podłączony"
  ok "CronJob ma REDIS_HOST (z pliku)"           applied ml cronjob/feature-pipeline REDIS_HOST
  ok "Redis ma cechy encji 42"                   bash -c "$K exec feature-store-0 -- redis-cli get features:42 | grep -q ."
  ok "inference ma REDIS_HOST (z pliku)"         applied ml deploy/inference REDIS_HOST
  ok "/predict/entity/42 → 200"                  http 200 localhost:30080/predict/entity/42
  ok "/predict/entity/9999 → 404"                http 404 localhost:30080/predict/entity/9999 ;;
I05) echo "I05 — API dla modeli"
  ok "/models/wine/version → 200"                http 200 http://api.127-0-0-1.nip.io/models/wine/version
  ok "/models/wine/predict → 200"                http 200 -XPOST http://api.127-0-0-1.nip.io/models/wine/predict -H 'content-type: application/json' -d "$PRED"
  ok "nagłówek x-served-by: fti-inference"       bash -c "curl -sI -m5 http://api.127-0-0-1.nip.io/models/wine/version | grep -qi 'x-served-by: fti-inference'"
  ok "inne ścieżki → 404"                        http 404 http://api.127-0-0-1.nip.io/metrics ;;
I06) echo "I06 — HPA (po przywróceniu requests)"
  ok "requests.cpu w Deploymencie (z pliku)"     applied ml deploy/inference '"cpu"'
  ok "HPA widzi metrykę CPU"                     has ml hpa/inference '{.status.currentMetrics[0].resource.current.averageUtilization}' '[0-9]'
  ok "HPA ScalingActive=True"                    has ml hpa/inference '{.status.conditions[?(@.type=="ScalingActive")].status}' True
  ok "scaleDown: max 1 Pod / 30 s"               eq ml hpa/inference '{.spec.behavior.scaleDown.policies[0].type}/{.spec.behavior.scaleDown.policies[0].value}/{.spec.behavior.scaleDown.policies[0].periodSeconds}' Pods/1/30 ;;
I07) echo "I07 — data-scientist i inference bez tokena"
  ok "data-scientist: get pods = yes"            can get pods
  no "data-scientist: get secrets = no"          can get secrets
  ok "data-scientist: exec do Poda = yes"        can create pods --subresource=exec
  no "data-scientist: delete jobs = no"          can delete jobs
  ok "inference: serviceAccountName z pliku"     applied ml deploy/inference serviceAccountName
  no "inference: brak tokena w Podzie"           $K exec deploy/inference -c server -- ls /var/run/secrets/kubernetes.io/serviceaccount/token ;;
I08) echo "I08 — overlay prod"
  ok "ml-prod: 3 gotowe repliki"                 eq ml-prod deploy/inference '{.status.readyReplicas}' 3
  ok "requests.cpu 250m"                         eq ml-prod deploy/inference '{.spec.template.spec.containers[0].resources.requests.cpu}' 250m
  ok "LOG_LEVEL=WARNING w ConfigMap"             bash -c "kubectl -n ml-prod get cm -o jsonpath='{.items[*].data.LOG_LEVEL}' | grep -q WARNING"
  ok "prod.127-0-0-1.nip.io/version → 200"       http 200 http://prod.127-0-0-1.nip.io/version ;;
I09) echo "I09 — własny chart fti-inference"
  CH=${CHART:-}; for c in "$LAB/work/09-helm/fti-inference" "$LAB/02-intermediate/09-helm/fti-inference"; do [ -z "$CH" ] && [ -f "$c/Chart.yaml" ] && CH=$c; done
  echo "  chart: ${CH:-(nie znaleziono — ustaw CHART=ścieżka)}"
  ok "helm lint"                                 helm lint "$CH"
  ok "gpu.count=1 → limit nvidia.com/gpu"        bash -c "helm template t '$CH' --set gpu.count=1 | grep -q 'nvidia.com/gpu: *\"\\?1'"
  ok "gpu.count=1 → toleration"                  bash -c "helm template t '$CH' --set gpu.count=1 | grep -q 'key: nvidia.com/gpu'"
  ok "gateway.enabled → HTTPRoute"               bash -c "helm template t '$CH' --set gateway.enabled=true | grep -q 'kind: HTTPRoute'"
  ok "featureCronjobs → CronJob(y)"              bash -c "helm template t '$CH' --set featureCronjobs.daily='0 3 * * *' | grep -q 'kind: CronJob'"
  ok "release wine w ml: deployed"               bash -c "helm status wine -n ml | grep -q 'STATUS: deployed'"
  ok "checksum/config w Podach release'u"        bash -c "helm get manifest wine -n ml | grep -q checksum/config" ;;
A01) echo "A01 — inference preferuje pulę CPU"
  ok "preferredDuringScheduling na pool=cpu"     has ml deploy/inference-ha '{.spec.template.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution}' cpu
  N=$($K get deploy inference-ha -o jsonpath='{.status.readyReplicas}')
  G=$($K get pods -l app=inference-ha -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | grep -c "$(kubectl get nodes -l pool=gpu -o name | cut -d/ -f2)")
  echo "  ℹ️  $N gotowych replik, z tego na puli GPU: $G (przy 4 replikach oczekiwane 0)"
  ok "wszystkie repliki gotowe"                  eq ml deploy/inference-ha '{.status.readyReplicas}' "$($K get deploy inference-ha -o jsonpath='{.spec.replicas}')" ;;
A02) echo "A02 — sweep w team-nlp"
  ok "Job hpo-team-nlp Complete"                 has team-nlp job/hpo-team-nlp '{.status.conditions[?(@.status=="True")].type}' Complete
  ok "8 ukończonych triali"                      eq team-nlp job/hpo-team-nlp '{.status.succeeded}' 8
  ok "trial: requests.cpu 1"                     eq team-nlp job/hpo-team-nlp '{.spec.template.spec.containers[0].resources.requests.cpu}' 1
  ok "quota zadziałała (FailedCreate)"           bash -c "kubectl -n team-nlp get events --field-selector reason=FailedCreate | grep -q 'exceeded quota'" ;;
A03) echo "A03 — sweep na GPU"
  ok "Job hpo-gpu Complete (5)"                  eq ml job/hpo-gpu '{.status.succeeded}' 5
  ok "trial: limit nvidia.com/gpu 1"             has ml job/hpo-gpu '{.spec.template.spec.containers[0].resources.limits}' nvidia.com/gpu
  ok "toleration nvidia.com/gpu"                 has ml job/hpo-gpu '{.spec.template.spec.tolerations}' nvidia.com/gpu
  ok "priorityClassName training-batch"          eq ml job/hpo-gpu '{.spec.template.spec.priorityClassName}' training-batch ;;
A05) echo "A05 — shadow i promocja (z plików)"
  ST=$(get ml httproute/wine '{.spec.rules[*].filters[*].type}')
  if [ "$ST" = RequestMirror ]; then
    ok "shadow: RequestMirror do wine-v2"        has ml httproute/wine '{.spec.rules[0].filters[0].requestMirror.backendRef.name}' wine-v2
    ok "shadow: odpowiada tylko wine-v1"         eq ml httproute/wine '{.spec.rules[0].backendRefs[*].name}' wine-v1
  else
    ok "promocja: 100% do wine-v2"               eq ml httproute/wine '{.spec.rules[*].backendRefs[*].name}' wine-v2
    ok "promocja: route z pliku (apply -f)"      applied ml httproute/wine wine-v2
    ok "wine-v1 przeskalowany do 0"              eq ml deploy/wine-v1 '{.spec.replicas}' 0
  fi ;;
A06) echo "A06 — NetworkPolicy"
  ok "default-deny istnieje"                     get ml netpol/default-deny '{.metadata.name}'
  ok "gateway → inference (/version 200)"        http 200 http://ml.127-0-0-1.nip.io/version
  ok "inference → Redis (/predict/entity/42 200)" http 200 http://ml.127-0-0-1.nip.io/predict/entity/42
  kubectl -n ml delete pod np-check --ignore-not-found >/dev/null 2>&1
  kubectl -n ml run np-check --image=curlimages/curl --restart=Never -- bash -c \
    'curl -s -m3 inference/version >/dev/null && echo INF; nc -z -w3 feature-store 6379 && echo REDIS; curl -s -m3 https://pypi.org >/dev/null && echo NET; echo done' >/dev/null 2>&1
  kubectl -n ml wait --for=jsonpath='{.status.phase}'=Succeeded pod/np-check --timeout=60s >/dev/null 2>&1
  L=$($K logs np-check 2>/dev/null); kubectl -n ml delete pod np-check --wait=false >/dev/null 2>&1
  no "obcy Pod → inference zablokowany"         grep -q INF <<<"$L"
  no "obcy Pod → Redis zablokowany"             grep -q REDIS <<<"$L"
  no "obcy Pod → internet zablokowany"          grep -q NET <<<"$L" ;;
A07) echo "A07 — PSA restricted i guardrails"
  ok "ns ml: enforce=restricted"                 bash -c "kubectl get ns ml -o jsonpath='{.metadata.labels.pod-security\\.kubernetes\\.io/enforce}' | grep -qx restricted"
  ok "Redis jako UID 999 i gotowy"               bash -c "[ \"\$($K exec feature-store-0 -- id -u)\" = 999 ] && [ \"\$($K get pod feature-store-0 -o jsonpath='{.status.containerStatuses[0].ready}')\" = true ]"
  ok "inference gotowy po utwardzeniu"           eq ml deploy/inference '{.status.readyReplicas}' "$($K get deploy inference -o jsonpath='{.spec.replicas}')"
  ok "CronJob: activeDeadlineSeconds (VAP)"      has ml cronjob/feature-pipeline '{.spec.jobTemplate.spec.activeDeadlineSeconds}' '[0-9]'
  ok "Job z CronJoba przechodzi PSA i VAP"       kubectl -n ml create job a07-check --from=cronjob/feature-pipeline --dry-run=server
  no "Pod root (busybox) odrzucony"              kubectl -n ml run a07-root --image=busybox:1.36 --dry-run=server -- true ;;
A08) echo "A08 — dashboard FTI"
  CM=$(kubectl -n monitoring get cm -l grafana_dashboard=1 -o json 2>/dev/null | python3 -c "import json,sys; print(next((n for i in json.load(sys.stdin)['items'] for n,v in i['data'].items() if '\"FTI\"' in v),''))")
  ok "ConfigMap z dashboardem \"FTI\" (grafana_dashboard=1)" test -n "$CM"
  ok "PodMonitor fti-inference"                  get ml podmonitor/fti-inference '{.metadata.name}'
  ok "reguły fti-alerts"                         get monitoring prometheusrule/fti-alerts '{.metadata.name}' ;;
A09) echo "A09 — 8 naprawionych workloadów"
  for d in 01 02 04 08; do ok "broken-$d: wszystkie repliki dostępne" eq debug deploy/broken-$d '{.status.availableReplicas}' "$(get debug deploy/broken-$d '{.spec.replicas}')"; done
  ok "broken-08: bez restartów (liveness nie zabija)" bash -c "[ -z \"\$(kubectl -n debug get pods -l app=broken-08 -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{\"\\n\"}{end}' | grep -v '^0\$')\" ]"
  for j in 03 06; do ok "broken-$j Complete" eq debug job/broken-$j '{.status.succeeded}' 1; done
  ok "broken-05: Service ma endpoint"            bash -c '[ $(ready_eps debug broken-05) -ge 1 ]'
  ok "broken-07: PVC Bound, Pod Running"         eq debug pvc/broken-07 '{.status.phase}' Bound ;;
A10) echo "A10 — platforma"
  ok "ns ml: PSA restricted + guardrails"        bash -c "kubectl get ns ml --show-labels | grep enforce=restricted | grep -q guardrails=enabled"
  ok "quota + LimitRange"                        bash -c "$K get resourcequota,limitrange --no-headers | grep -q ."
  ok "default-deny"                              get ml netpol/default-deny '{.metadata.name}'
  ok "inference gotowy, PDB, HPA"                bash -c "$K get pdb,hpa --no-headers | grep -c . | grep -qv '^[01]$' && [ \"\$($K get deploy inference -o jsonpath='{.status.readyReplicas}')\" -ge 2 ]"
  ok "change-cause w historii"                   has ml deploy/inference '{.metadata.annotations.kubernetes\.io/change-cause}' model
  ok "ml.127-0-0-1.nip.io/predict → 200"         http 200 -XPOST http://ml.127-0-0-1.nip.io/predict -H 'content-type: application/json' -d "$PRED"
  ok "Ollama gotowa (priorityClass)"             eq llm deploy/ollama '{.status.readyReplicas}/{.spec.template.spec.priorityClassName}' 1/inference-critical
  ok "llm-eval przeszedł bramkę"                 eq llm job/llm-eval '{.status.succeeded}' 1
  ok "ns llm: default-deny"                      get llm netpol/default-deny '{.metadata.name}' ;;
*) echo "Użycie: $0 <lab>   np. $0 B03"
   echo "Ćwiczenia ze sprawdzaniem: B01 B03 B04 B05 B06 B07 I01 I02 I03 I04 I05 I06 I07 I08 I09 A01 A02 A03 A05 A06 A07 A08 A09 A10"
   exit 2 ;;
esac
echo "  wynik: $PASS ✅  $FAIL ❌"
[ "$FAIL" = 0 ]
