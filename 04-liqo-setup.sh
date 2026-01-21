#!/bin/bash
#
# 05-liqo-setup.sh - Installazione Liqo
# Installa Liqo per multi-cluster Kubernetes
#

set -e

# Colori
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

log_info "Installazione Liqo..."

# Liqo version
LIQO_VERSION="${LIQO_VERSION:-v0.10.3}"
log_info "Versione Liqo: $LIQO_VERSION"

# Setup kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Check Kubernetes is ready
if ! kubectl get nodes &> /dev/null; then
    log_error "Kubernetes non è accessibile. Verifica che K3s sia in esecuzione."
    exit 1
fi

# Install liqoctl (Liqo CLI)
log_info "Download e installazione liqoctl..."

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        LIQO_ARCH="amd64"
        ;;
    aarch64)
        LIQO_ARCH="arm64"
        ;;
    *)
        log_error "Architettura non supportata: $ARCH"
        exit 1
        ;;
esac

# Download liqoctl
LIQOCTL_URL="https://github.com/liqotech/liqo/releases/download/${LIQO_VERSION}/liqoctl-linux-${LIQO_ARCH}"
log_info "Download da: $LIQOCTL_URL"

curl -fsSL "$LIQOCTL_URL" -o /usr/local/bin/liqoctl
chmod +x /usr/local/bin/liqoctl

# Verify liqoctl installation
if ! command -v liqoctl &> /dev/null; then
    log_error "Installazione liqoctl fallita"
    exit 1
fi

log_success "liqoctl installato: $(liqoctl version --client)"

# Get cluster information
CLUSTER_NAME="${CLUSTER_NAME:-demo-cluster}"
CLUSTER_IP=$(hostname -I | awk '{print $1}')

log_info "Nome cluster: $CLUSTER_NAME"
log_info "IP cluster: $CLUSTER_IP"

# Install Liqo on the cluster
log_info "Installazione Liqo sul cluster..."

# Create Liqo namespace
kubectl create namespace liqo-system || true

# Install Liqo using liqoctl
liqoctl install k3s \
    --cluster-name="$CLUSTER_NAME" \
    --version="$LIQO_VERSION" \
    --set networking.internal=true \
    --set gateway.service.type=NodePort

log_info "Attesa completamento installazione Liqo..."
sleep 15

# Wait for Liqo pods to be ready
log_info "Attesa avvio pod Liqo..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=liqo -n liqo-system --timeout=300s || {
    log_warning "Alcuni pod Liqo potrebbero richiedere più tempo"
    kubectl get pods -n liqo-system
}

# Display Liqo status
log_info "Stato Liqo:"
liqoctl status

# Get Liqo pods
log_info "Pod Liqo:"
kubectl get pods -n liqo-system

# Create Liqo peering example scripts
cat > /opt/liqo-demo/liqo-peer-example.sh <<'EOF'
#!/bin/bash
# Esempio di peering tra due cluster Liqo
#
# NOTA: Questo script è un esempio. Per creare un vero peering,
# hai bisogno di due cluster separati.
#
# Uso:
# 1. Sul cluster remoto, genera un token:
#    liqoctl generate peer-command
#
# 2. Esegui il comando generato su questo cluster:
#    liqoctl peer out-of-band <REMOTE_CLUSTER_NAME> \
#      --auth-url <AUTH_URL> --cluster-token <TOKEN>

echo "=== Liqo Peering Example ==="
echo ""
echo "Step 1: Sul cluster REMOTO, genera un peer command:"
echo "  liqoctl generate peer-command"
echo ""
echo "Step 2: Copia ed esegui il comando su QUESTO cluster"
echo ""
echo "Step 3: Verifica il peering:"
echo "  liqoctl status peer"
echo "  kubectl get foreignclusters"
echo ""
echo "Step 4: Per unpeer:"
echo "  liqoctl unpeer out-of-band <remote-cluster-name>"
EOF

chmod +x /opt/liqo-demo/liqo-peer-example.sh

# Create Liqo offloading example
cat > /opt/liqo-demo/liqo-offload-example.yaml <<'EOF'
# Esempio di deployment con offloading Liqo
# Questo deployment può essere schedulato su cluster remoti
apiVersion: apps/v1
kind: Deployment
metadata:
  name: liqo-demo-app
  namespace: liqo-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: liqo-demo
  template:
    metadata:
      labels:
        app: liqo-demo
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: liqo-demo-service
  namespace: liqo-demo
spec:
  selector:
    app: liqo-demo
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

# Create Liqo helper scripts
cat > /opt/liqo-demo/liqo-info.sh <<'EOF'
#!/bin/bash
echo "=== Liqo Status ==="
echo ""
echo "1. Liqo version:"
liqoctl version
echo ""
echo "2. Cluster status:"
liqoctl status
echo ""
echo "3. Foreign clusters:"
kubectl get foreignclusters -A
echo ""
echo "4. Liqo pods:"
kubectl get pods -n liqo-system
echo ""
echo "5. Virtual nodes:"
kubectl get nodes -l liqo.io/type=virtual-node
echo ""
echo "6. Offloaded namespaces:"
kubectl get namespaces -l liqo.io/scheduling-enabled=true
EOF

chmod +x /opt/liqo-demo/liqo-info.sh

# Create namespace offloading helper
cat > /opt/liqo-demo/liqo-enable-offload.sh <<'EOF'
#!/bin/bash
# Script per abilitare l'offloading su un namespace

if [ -z "$1" ]; then
    echo "Uso: $0 <namespace>"
    echo ""
    echo "Abilita l'offloading Liqo su un namespace specifico"
    exit 1
fi

NAMESPACE=$1

echo "Abilitazione offloading per namespace: $NAMESPACE"

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# Enable Liqo offloading
liqoctl offload namespace "$NAMESPACE"

echo ""
echo "Offloading abilitato su namespace: $NAMESPACE"
echo ""
echo "Verifica:"
kubectl get namespace "$NAMESPACE" -o yaml | grep liqo.io
EOF

chmod +x /opt/liqo-demo/liqo-enable-offload.sh

# Create documentation
cat > /opt/liqo-demo/README-LIQO.md <<'EOF'
# Liqo Demo Setup

## Cosa è Liqo?

Liqo è una piattaforma open-source che consente la federazione di cluster Kubernetes multipli, permettendo:
- **Offloading** di workload tra cluster
- **Networking** trasparente tra cluster
- **Resource sharing** dinamico
- **Multi-cluster scheduling**

## Comandi Principali

### Stato Cluster
```bash
# Verifica installazione Liqo
liqoctl version

# Stato generale
liqoctl status

# Info dettagliate
./liqo-info.sh
```

### Peering tra Cluster
```bash
# Genera comando di peering (su cluster remoto)
liqoctl generate peer-command

# Esegui peering (su questo cluster)
liqoctl peer out-of-band <nome-cluster-remoto> \
  --auth-url <url> --cluster-token <token>

# Verifica peering
liqoctl status peer
kubectl get foreignclusters
```

### Offloading
```bash
# Abilita offloading su namespace
liqoctl offload namespace liqo-demo

# Oppure usa lo script helper
./liqo-enable-offload.sh my-namespace

# Verifica namespace con offloading
kubectl get namespaces -l liqo.io/scheduling-enabled=true
```

### Deploy Applicazioni
```bash
# Deploy esempio con offloading
kubectl apply -f liqo-offload-example.yaml

# Verifica scheduling
kubectl get pods -n liqo-demo -o wide

# I pod possono essere schedulati su:
# - Nodi locali
# - Virtual nodes (che rappresentano cluster remoti)
```

## Architettura

```
┌─────────────────┐         ┌─────────────────┐
│   Cluster 1     │         │   Cluster 2     │
│   (Questo)      │◄───────►│   (Remoto)      │
│                 │  Liqo   │                 │
│  ┌───────────┐  │ Peering │  ┌───────────┐  │
│  │   Pods    │  │         │  │   Pods    │  │
│  └───────────┘  │         │  └───────────┘  │
│                 │         │                 │
│  Virtual Node ──┼────────►│  Real Nodes     │
│  (Cluster 2)    │         │                 │
└─────────────────┘         └─────────────────┘
```

## Scenario Demo

### 1. Single Cluster (Attuale)
- Cluster K3s locale con Liqo installato
- Pronto per peering con altri cluster
- Namespace `liqo-demo` configurato

### 2. Multi-Cluster (Richiede secondo cluster)
Per testare il vero offloading:

1. Setup secondo cluster (può essere anche cloud)
2. Installa Liqo su entrambi
3. Crea peering tra i cluster
4. Abilita offloading su namespace
5. Deploy applicazioni che si distribuiscono automaticamente

## File Utili

- `liqo-info.sh` - Informazioni stato Liqo
- `liqo-peer-example.sh` - Esempio peering
- `liqo-enable-offload.sh` - Abilita offloading namespace
- `liqo-offload-example.yaml` - Deployment esempio

## Troubleshooting

### Verificare pod Liqo
```bash
kubectl get pods -n liqo-system
kubectl logs -n liqo-system -l app.kubernetes.io/name=liqo-controller-manager
```

### Verificare networking
```bash
kubectl get networkconfigs -A
kubectl get ipamstorages -A
```

### Reset peering
```bash
liqoctl unpeer out-of-band <cluster-name>
```

## Link Utili

- Documentazione: https://docs.liqo.io
- GitHub: https://github.com/liqotech/liqo
- Esempi: https://github.com/liqotech/liqo/tree/master/examples

EOF

log_success "Installazione Liqo completata!"
log_info ""
log_info "File creati in /opt/liqo-demo/:"
ls -lh /opt/liqo-demo/liqo-* /opt/liqo-demo/README-LIQO.md 2>/dev/null
log_info ""

# Copy GPU test script if exists
if [ -f "./test-liqo-gpu.sh" ]; then
    cp ./test-liqo-gpu.sh /opt/liqo-demo/
    chmod +x /opt/liqo-demo/test-liqo-gpu.sh
    log_success "Script test GPU copiato: /opt/liqo-demo/test-liqo-gpu.sh"
fi

log_info "Comandi utili:"
echo "  liqoctl version          # Versione Liqo"
echo "  liqoctl status           # Stato cluster"
echo "  ./liqo-info.sh           # Info dettagliate"
echo "  ./test-liqo-gpu.sh       # Test completo GPU con Liqo"
echo ""
log_info "Per iniziare:"
echo "  cat /opt/liqo-demo/README-LIQO.md"
