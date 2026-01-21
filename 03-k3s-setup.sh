#!/bin/bash
#
# 03-k3s-setup.sh - Installazione Kubernetes con K3s
# Installa K3s (lightweight Kubernetes) con supporto GPU usando containerd
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

log_info "Installazione Kubernetes (K3s)..."

# K3s version
K3S_VERSION="${K3S_VERSION:-v1.28.5+k3s1}"
log_info "Versione K3s: $K3S_VERSION"

# Check if K3s is already installed
if command -v k3s &> /dev/null; then
    CURRENT_VERSION=$(k3s --version | head -n1)
    log_info "K3s già installato: $CURRENT_VERSION"
    read -p "Vuoi reinstallare K3s? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skip reinstallazione K3s"
        exit 0
    fi
    
    # Uninstall existing K3s
    log_info "Disinstallazione K3s esistente..."
    /usr/local/bin/k3s-uninstall.sh || true
    sleep 5
fi

# Prepare K3s installation
log_info "Preparazione installazione K3s..."

# Create K3s config directory
mkdir -p /etc/rancher/k3s

# Determine if GPU support should be enabled
GPU_SUPPORT="false"
if command -v nvidia-smi &> /dev/null && [ -f /usr/bin/nvidia-container-runtime ]; then
    GPU_SUPPORT="true"
    log_info "Supporto GPU abilitato"
fi

# Create K3s config file
cat > /etc/rancher/k3s/config.yaml <<EOF
# K3s Configuration for Liqo Demo
# GPU Support: $GPU_SUPPORT

# Cluster configuration
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
cluster-dns: "10.43.0.10"

# Disable components we don't need for demo
disable:
  - traefik
  - servicelb

# Network configuration
flannel-backend: "vxlan"

# TLS configuration
tls-san:
  - "$(hostname)"
  - "$(hostname -I | awk '{print $1}')"

# Write kubeconfig with proper permissions
write-kubeconfig-mode: "0644"

# Container runtime
container-runtime-endpoint: "unix:///run/containerd/containerd.sock"
EOF

log_success "File di configurazione K3s creato"

# Install K3s
log_info "Download e installazione K3s..."

# Set installation options
export INSTALL_K3S_VERSION="$K3S_VERSION"
export INSTALL_K3S_EXEC="server --config=/etc/rancher/k3s/config.yaml"

# Download and run K3s installer
curl -sfL https://get.k3s.io | sh -

# Wait for K3s to be ready
log_info "Attesa avvio K3s..."
sleep 10

# Check K3s status
for i in {1..30}; do
    if systemctl is-active --quiet k3s; then
        log_success "K3s service attivo"
        break
    fi
    if [ $i -eq 30 ]; then
        log_error "K3s service non si è avviato"
        systemctl status k3s
        exit 1
    fi
    sleep 2
done

# Configure containerd for GPU if available
if [ "$GPU_SUPPORT" == "true" ]; then
    log_info "Configurazione containerd per GPU support..."
    
    # Backup original config
    cp /var/lib/rancher/k3s/agent/etc/containerd/config.toml /var/lib/rancher/k3s/agent/etc/containerd/config.toml.bak
    
    # Add NVIDIA runtime to containerd config
    cat >> /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl <<EOF

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
    SystemdCgroup = true
EOF
    
    # Restart K3s to apply containerd changes
    systemctl restart k3s
    sleep 10
    
    log_success "containerd configurato per GPU"
fi

# Setup kubectl
log_info "Configurazione kubectl..."

# Create kubectl alias and kubeconfig
cat >> /root/.bashrc <<'EOF'

# Kubernetes aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgn='kubectl get nodes'
alias kgs='kubectl get svc'
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
EOF

# Export for current session
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Install kubectl completion
kubectl completion bash > /etc/bash_completion.d/kubectl

# Wait for node to be ready
log_info "Attesa che il node sia Ready..."
for i in {1..60}; do
    if kubectl get nodes 2>/dev/null | grep -q "Ready"; then
        log_success "Node Kubernetes Ready!"
        break
    fi
    if [ $i -eq 60 ]; then
        log_error "Node non è diventato Ready entro il timeout"
        kubectl get nodes
        exit 1
    fi
    sleep 5
done

# Display cluster info
log_info "Informazioni cluster:"
kubectl get nodes -o wide
kubectl get pods -A

# Install NVIDIA device plugin if GPU is available
if [ "$GPU_SUPPORT" == "true" ]; then
    log_info "Installazione NVIDIA Device Plugin per Kubernetes..."
    
    kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml
    
    log_info "Attesa avvio NVIDIA Device Plugin..."
    sleep 10
    
    # Wait for device plugin to be ready
    kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=120s || log_warning "NVIDIA Device Plugin potrebbe richiedere più tempo"
    
    log_success "NVIDIA Device Plugin installato"
fi

# Create namespace for demos
log_info "Creazione namespace per demo..."
kubectl create namespace liqo-demo || true
kubectl label namespace liqo-demo liqo.io/enabled=true || true

# Create test deployment
log_info "Creazione test deployment..."
cat > /opt/liqo-demo/test-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-nginx
  namespace: liqo-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-nginx
  template:
    metadata:
      labels:
        app: test-nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-nginx
  namespace: liqo-demo
spec:
  selector:
    app: test-nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

kubectl apply -f /opt/liqo-demo/test-deployment.yaml
log_success "Test deployment creato"

# Create GPU test if available
if [ "$GPU_SUPPORT" == "true" ]; then
    cat > /opt/liqo-demo/test-gpu-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: liqo-demo
spec:
  restartPolicy: OnFailure
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    log_info "File test GPU creato: /opt/liqo-demo/test-gpu-pod.yaml"
    log_info "Per testare GPU: kubectl apply -f /opt/liqo-demo/test-gpu-pod.yaml"
fi

# Create helper scripts
cat > /opt/liqo-demo/k8s-info.sh <<'EOF'
#!/bin/bash
echo "=== Kubernetes Cluster Info ==="
echo ""
echo "Nodes:"
kubectl get nodes -o wide
echo ""
echo "Namespaces:"
kubectl get namespaces
echo ""
echo "All Pods:"
kubectl get pods -A
echo ""
echo "Services in liqo-demo:"
kubectl get svc -n liqo-demo
echo ""
echo "GPU Resources (if available):"
kubectl get nodes -o json | jq '.items[].status.capacity | select(.["nvidia.com/gpu"]) | .["nvidia.com/gpu"]' 2>/dev/null || echo "No GPU resources found"
EOF

chmod +x /opt/liqo-demo/k8s-info.sh

log_success "Installazione K3s completata!"
log_info ""
log_info "Kubeconfig: /etc/rancher/k3s/k3s.yaml"
log_info "Per usare kubectl: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
log_info "Script info cluster: /opt/liqo-demo/k8s-info.sh"
log_info ""
log_info "Comandi utili:"
echo "  kubectl get nodes"
echo "  kubectl get pods -A"
echo "  kubectl cluster-info"
