# Źródłuj w każdym nowym terminalu:  source setup/env.sh
# Osobny kubeconfig -> główny ~/.kube/config zostaje nietknięty.
export CLUSTER=mlops
# kind/kubectl/helm instalowane przez prereq.sh lądują w ~/.local/bin
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
export KUBECONFIG="$HOME/.kube/kind-mlops.yaml"
# Katalog hosta montowany we WSZYSTKICH węzłach jako /mnt/shared
# (udaje współdzielony storage typu NFS/S3 -> rejestr modeli widoczny z każdego węzła).
export LAB_DATA="$HOME/k8s-lab-data"
# Twoje manifesty z ćwiczeń (pliki w labach zostają nietkniętymi przykładami)
export WORK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/work"
mkdir -p "$WORK"
alias k=kubectl
source <(kubectl completion bash) 2>/dev/null && complete -o default -F __start_kubectl k
