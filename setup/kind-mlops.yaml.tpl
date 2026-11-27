# Klaster labowy: 1 control-plane + 2 workery.
# Generowany przez up.sh (sed wstawia ${LAB_DATA}) -> kind-mlops.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: mlops
# Bind-addressy pod kube-prometheus-stack (lab advanced/08) — ustawione od razu,
# żeby nie odtwarzać klastra.
kubeadmConfigPatches:
- |-
  kind: ClusterConfiguration
  controllerManager:
    extraArgs:
      bind-address: 0.0.0.0
  etcd:
    local:
      extraArgs:
        listen-metrics-urls: http://0.0.0.0:2381
  scheduler:
    extraArgs:
      bind-address: 0.0.0.0
- |-
  kind: KubeProxyConfiguration
  metricsBindAddress: 0.0.0.0
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  # Gateway API (Envoy) wystawiony przez hostPort na control-plane (lab intermediate/05)
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
  - containerPort: 443
    hostPort: 443
  extraMounts:
  - hostPath: ${LAB_DATA}
    containerPath: /mnt/shared
- role: worker
  extraPortMappings:
  - containerPort: 30080      # NodePort z labu basic/04
    hostPort: 30080
  extraMounts:
  - hostPath: ${LAB_DATA}
    containerPath: /mnt/shared
- role: worker
  extraMounts:
  - hostPath: ${LAB_DATA}
    containerPath: /mnt/shared
