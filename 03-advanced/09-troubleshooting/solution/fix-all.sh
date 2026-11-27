#!/usr/bin/env bash
# Naprawy wszystkich 8 workloadów z broken/ (sprawdzone 2026-11-27). Działa z dowolnego katalogu.
set -euo pipefail
cd "$(dirname "$0")/.."      # broken/ leży w katalogu laba
D="-n debug"
# 01: tag, który jest w kind + IfNotPresent
kubectl $D set image deploy/broken-01 server=fti-lab:0.1
kubectl $D patch deploy broken-01 --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/imagePullPolicy","value":"IfNotPresent"}]'
# 02: literówka w module uvicorn
kubectl $D patch deploy broken-02 --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command/1","value":"fti.serve:app"}]'
# 03: realne requests (Job jest niezmienny w template -> odtwarzamy)
kubectl $D delete job broken-03 ; sed 's/cpu: "64"/cpu: "1"/' broken/03.yaml | kubectl apply -f -
# 04: model, który istnieje (wypalony w obrazie)
kubectl $D set env deploy/broken-04 MODEL_PATH=/opt/model/model.joblib
# 05: selektor i targetPort
kubectl $D patch svc broken-05 --type=merge -p '{"spec":{"selector":{"app":"broken-05","tier":"model"},"ports":[{"port":80,"targetPort":8080}]}}'
# 06: pamięć dla 3000 drzew
kubectl $D delete job broken-06 ; sed 's/memory: 96Mi/memory: 1Gi/; s/memory: 64Mi/memory: 256Mi/' broken/06.yaml | kubectl apply -f -
# 07: istniejąca StorageClass (PVC jest niezmienny -> odtwarzamy)
kubectl $D delete pod broken-07 ; kubectl $D delete pvc broken-07
sed 's/storageClassName: fast-nvme/storageClassName: standard/' broken/07.yaml | kubectl apply -f -
# 08: startupProbe + liveness na /healthz
kubectl $D patch deploy broken-08 --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/healthz"},{"op":"add","path":"/spec/template/spec/containers/0/startupProbe","value":{"httpGet":{"path":"/ready","port":"http"},"periodSeconds":5,"failureThreshold":30}}]'
echo "Po ~1 min: kubectl get pods,pvc -n debug"
