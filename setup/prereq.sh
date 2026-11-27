#!/usr/bin/env bash
# Sprawdza narzędzia potrzebne w labach i doinstalowuje BRAKUJĄCE (bez sudo, do ~/.local/bin).
#   ./setup/prereq.sh            # sprawdź + zainstaluj brakujące kind / kubectl / helm
#   ./setup/prereq.sh --check    # tylko sprawdź, nic nie instaluj
# Zasada: jeśli narzędzie już jest — używamy go (najwyżej ostrzeżenie o wersji).
# Docker wymaga sudo → skrypt go nie instaluje, tylko podaje polecenia.
set -euo pipefail

# Wersje, na których laby są przetestowane
KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.37.2
HELM_VERSION=v4.3.2
KIND_MIN=0.24.0          # od 0.24 kindnet egzekwuje NetworkPolicy (A06)
HELM_MIN=4.0.0           # README używa flag Helma 4 (np. --rollback-on-failure)

BIN=${INSTALL_DIR:-$HOME/.local/bin}
CHECK_ONLY=0; [[ "${1:-}" == "--check" ]] && CHECK_ONLY=1
ORIG_PATH=$PATH
case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac

case "$(uname -m)" in
  x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;;
  *) echo "❌ nieobsługiwana architektura: $(uname -m)"; exit 1 ;;
esac

ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }
bad()  { echo "  ❌ $*"; FAIL=1; }
FAIL=0
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }   # $1 >= $2

# pobranie + weryfikacja sumy SHA-256 (plik sumy z oficjalnego źródła)
fetch() {  # url plik url_sumy
  curl -fsSLo "$2" "$1"
  local want; want=$(curl -fsSL "$3" | awk '{print $1}')
  echo "$want  $2" | sha256sum -c --quiet - || { echo "❌ zła suma SHA-256: $1"; rm -f "$2"; exit 1; }
}

install_tool() {
  local name=$1 tmp; tmp=$(mktemp -d); mkdir -p "$BIN"
  case $name in
    kind)
      local u="https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-$ARCH"
      fetch "$u" "$tmp/kind" "$u.sha256sum"; install -m 0755 "$tmp/kind" "$BIN/kind" ;;
    kubectl)
      local u="https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl"
      fetch "$u" "$tmp/kubectl" "$u.sha256"; install -m 0755 "$tmp/kubectl" "$BIN/kubectl" ;;
    helm)
      local u="https://get.helm.sh/helm-$HELM_VERSION-linux-$ARCH.tar.gz"
      fetch "$u" "$tmp/helm.tgz" "$u.sha256sum"
      tar -xzf "$tmp/helm.tgz" -C "$tmp"; install -m 0755 "$tmp/linux-$ARCH/helm" "$BIN/helm" ;;
  esac
  rm -rf "$tmp"
}

echo "Narzędzia:"
# --- Docker: tylko sprawdzamy
if ! command -v docker >/dev/null; then
  bad "docker — brak. Zainstaluj (raz, z sudo), potem wyloguj się i zaloguj:"
  echo "       curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker \$USER"
elif ! docker info >/dev/null 2>&1; then
  bad "docker jest, ale nie masz dostępu do demona (grupa docker?):"
  echo "       sudo usermod -aG docker \$USER   # i ponowne zalogowanie"
else
  ok "docker $(docker version --format '{{.Server.Version}}')"
fi

command -v curl >/dev/null || { bad "curl — brak (sudo apt install -y curl)"; }

# --- kind / kubectl / helm: jest → używamy; brak → instalujemy
for t in kind kubectl helm; do
  if command -v $t >/dev/null; then
    case $t in
      kind)    v=$(kind version | awk '{print $2}'); v=${v#v}
               ver_ge "$v" "$KIND_MIN" && ok "kind v$v ($(command -v kind))" \
                 || warn "kind v$v < $KIND_MIN — NetworkPolicy (A06) nie zadziała; usuń go, a skrypt wstawi $KIND_VERSION" ;;
      kubectl) v=$(kubectl version --client -o json 2>/dev/null | sed -n 's/.*"gitVersion": *"v\([^"]*\)".*/\1/p' | head -1)
               ok "kubectl v$v ($(command -v kubectl))" ;;
      helm)    v=$(helm version --template '{{.Version}}' 2>/dev/null); v=${v#v}
               ver_ge "$v" "$HELM_MIN" && ok "helm v$v ($(command -v helm))" \
                 || warn "helm v$v — laby zakładają Helm 4 (różnice w flagach, np. --atomic → --rollback-on-failure)" ;;
    esac
  elif [ $CHECK_ONLY = 1 ]; then
    bad "$t — brak (./setup/prereq.sh zainstaluje go do $BIN)"
  else
    case $t in kind) V=$KIND_VERSION ;; kubectl) V=$KUBECTL_VERSION ;; helm) V=$HELM_VERSION ;; esac
    echo "  ⬇️  $t — brak, instaluję $V do $BIN ..."
    install_tool $t && ok "$t $V zainstalowany"
  fi
done

# --- Zasoby hosta (ostrzeżenia, nie błędy)
echo "Host:"
CPU=$(nproc); MEM=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
[ "$CPU" -ge 4 ] && [ "$MEM" -ge 8 ] && ok "$CPU CPU, $MEM GB RAM" \
  || warn "$CPU CPU, $MEM GB RAM — basic potrzebuje ~4 CPU / 8 GB"
[ "$CPU" -ge 8 ] && [ "$MEM" -ge 16 ] || warn "advanced (monitoring A08, Ollama A10) potrzebuje ~8 CPU / 16 GB"
INO=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)
[ "$INO" -ge 512 ] && ok "inotify max_user_instances=$INO" \
  || warn "inotify max_user_instances=$INO — przy 3 węzłach kind bywa 'too many open files'; sudo sysctl fs.inotify.max_user_instances=512"
if [ -e /dev/kmsg ] && ! [ -r /dev/kmsg ]; then
  warn "brak odczytu /dev/kmsg (typowe w LXC) — kubelet w kind może nie wstać; potrzebna poprawka na hoście kontenera"
fi
case ":$ORIG_PATH:" in *":$BIN:"*) ;; *) warn "$BIN nie jest w Twoim PATH — dodaje go 'source setup/env.sh'" ;; esac

echo
if [ $FAIL = 1 ]; then echo "❌ Popraw powyższe i uruchom ponownie."; exit 1; fi
echo "✅ Gotowe do labów."
