#!/bin/bash
#
# test-liqo-gpu.sh - Test Completo GPU con Liqo
# Verifica che le GPU siano esposte correttamente attraverso Liqo
#

set -e

# Colori
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

FAILED_TESTS=0

print_banner() {
    echo ""
    echo "=========================================="
    echo "  Test GPU con Liqo"
    echo "=========================================="
    echo ""
}

# Setup kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

print_banner

# Test 1: Verifica GPU su nodo locale
log_info "Test 1: Verifica GPU disponibili sul nodo locale"
echo ""

GPU_CAPACITY=$(kubectl get nodes -o json | jq -r '.items[0].status.capacity["nvidia.com/gpu"]' 2>/dev/null)

if [ "$GPU_CAPACITY" != "null" ] && [ -n "$GPU_CAPACITY" ]; then
    log_success "GPU trovate sul nodo locale: $GPU_CAPACITY"
    
    # Mostra dettagli GPU
    log_info "Dettagli GPU:"
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv,noheader | while read line; do
            echo "    $line"
        done
    fi
else
    log_error "Nessuna GPU trovata sul nodo locale"
    ((FAILED_TESTS++))
fi

echo ""

# Test 2: Verifica NVIDIA Device Plugin
log_info "Test 2: Verifica NVIDIA Device Plugin"
echo ""

DEVICE_PLUGIN_PODS=$(kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds --no-headers 2>/dev/null | wc -l)

if [ "$DEVICE_PLUGIN_PODS" -gt 0 ]; then
    RUNNING_PODS=$(kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [ "$RUNNING_PODS" -gt 0 ]; then
        log_success "NVIDIA Device Plugin: $RUNNING_PODS/$DEVICE_PLUGIN_PODS pod Running"
    else
        log_error "NVIDIA Device Plugin: Nessun pod Running"
        ((FAILED_TESTS++))
    fi
else
    log_warning "NVIDIA Device Plugin: Non installato"
    log_info "Per installare: kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml"
fi

echo ""

# Test 3: Verifica Liqo
log_info "Test 3: Verifica installazione Liqo"
echo ""

if command -v liqoctl &> /dev/null; then
    log_success "liqoctl installato"
    
    # Verifica Liqo pods
    LIQO_PODS=$(kubectl get pods -n liqo-system --no-headers 2>/dev/null | wc -l)
    LIQO_RUNNING=$(kubectl get pods -n liqo-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    
    if [ "$LIQO_RUNNING" -eq "$LIQO_PODS" ] && [ "$LIQO_PODS" -gt 0 ]; then
        log_success "Liqo pods: $LIQO_RUNNING/$LIQO_PODS Running"
    else
        log_warning "Liqo pods: $LIQO_RUNNING/$LIQO_PODS Running"
    fi
else
    log_error "liqoctl non installato"
    ((FAILED_TESTS++))
fi

echo ""

# Test 4: Verifica Foreign Clusters e Virtual Nodes
log_info "Test 4: Verifica Foreign Clusters e Virtual Nodes"
echo ""

FOREIGN_CLUSTERS=$(kubectl get foreignclusters --no-headers 2>/dev/null | wc -l)

if [ "$FOREIGN_CLUSTERS" -gt 0 ]; then
    log_success "Foreign Clusters trovati: $FOREIGN_CLUSTERS"
    kubectl get foreignclusters -o custom-columns=NAME:.metadata.name,OUTGOING:.status.peeringConditions[0].status,INCOMING:.status.peeringConditions[1].status,AGE:.metadata.creationTimestamp --no-headers
    
    # Verifica Virtual Nodes
    VIRTUAL_NODES=$(kubectl get nodes -l liqo.io/type=virtual-node --no-headers 2>/dev/null | wc -l)
    if [ "$VIRTUAL_NODES" -gt 0 ]; then
        log_success "Virtual Nodes trovati: $VIRTUAL_NODES"
        
        # Verifica GPU su Virtual Nodes
        log_info "Verifica GPU su Virtual Nodes:"
        kubectl get nodes -l liqo.io/type=virtual-node -o json | jq -r '.items[] | "\(.metadata.name): \(.status.capacity["nvidia.com/gpu"] // "0") GPU"' | while read line; do
            if [[ "$line" == *": 0 GPU"* ]] || [[ "$line" == *": null GPU"* ]]; then
                echo "    $line (no GPU)"
            else
                echo "    ✓ $line"
            fi
        done
    else
        log_info "Virtual Nodes: Nessuno trovato (normale se non c'è peering attivo)"
    fi
else
    log_info "Foreign Clusters: Nessuno trovato (normale se non c'è peering configurato)"
fi

echo ""

# Test 5: Deploy GPU Pod Test
log_info "Test 5: Deploy e test GPU pod"
echo ""

# Create namespace if not exists
kubectl create namespace liqo-demo 2>/dev/null || true

# Create GPU test pod
cat > /tmp/test-gpu-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-liqo
  namespace: liqo-demo
  labels:
    app: gpu-test
spec:
  restartPolicy: Never
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command:
      - /bin/bash
      - -c
      - |
        echo "=== GPU Test Starting ==="
        echo "Hostname: $(hostname)"
        echo "Date: $(date)"
        echo ""
        echo "=== NVIDIA SMI Output ==="
        nvidia-smi
        echo ""
        echo "=== GPU Query ==="
        nvidia-smi --query-gpu=index,name,memory.total,memory.free,memory.used --format=csv
        echo ""
        echo "=== Test Completed Successfully ==="
    resources:
      limits:
        nvidia.com/gpu: 1
      requests:
        memory: "512Mi"
        cpu: "500m"
EOF

log_info "Deploying GPU test pod..."
kubectl delete pod gpu-test-liqo -n liqo-demo 2>/dev/null || true
sleep 2

if kubectl apply -f /tmp/test-gpu-pod.yaml; then
    log_info "Waiting for pod to complete (max 120s)..."
    
    # Wait for pod to complete or fail
    for i in {1..60}; do
        POD_STATUS=$(kubectl get pod gpu-test-liqo -n liqo-demo -o jsonpath='{.status.phase}' 2>/dev/null)
        
        if [ "$POD_STATUS" == "Succeeded" ]; then
            log_success "GPU test pod completato con successo!"
            echo ""
            log_info "Output del test:"
            echo "-----------------------------------"
            kubectl logs gpu-test-liqo -n liqo-demo
            echo "-----------------------------------"
            break
        elif [ "$POD_STATUS" == "Failed" ]; then
            log_error "GPU test pod fallito"
            kubectl logs gpu-test-liqo -n liqo-demo
            kubectl describe pod gpu-test-liqo -n liqo-demo | tail -20
            ((FAILED_TESTS++))
            break
        elif [ "$POD_STATUS" == "Pending" ] && [ $i -gt 30 ]; then
            log_warning "Pod ancora in Pending dopo 30s..."
            kubectl describe pod gpu-test-liqo -n liqo-demo | grep -A 10 "Events:"
        fi
        
        sleep 2
    done
    
    if [ "$POD_STATUS" != "Succeeded" ] && [ "$POD_STATUS" != "Failed" ]; then
        log_warning "Timeout: pod non completato entro 120s (status: $POD_STATUS)"
        ((FAILED_TESTS++))
    fi
else
    log_error "Impossibile creare GPU test pod"
    ((FAILED_TESTS++))
fi

echo ""

# Test 6: Verifica GPU Allocation
log_info "Test 6: Verifica allocazione GPU"
echo ""

# Check current GPU allocation
ALLOCATED_GPUS=$(kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits["nvidia.com/gpu"]) | "\(.metadata.namespace)/\(.metadata.name)"' | wc -l)

log_info "Pod con GPU allocate: $ALLOCATED_GPUS"

if [ "$ALLOCATED_GPUS" -gt 0 ]; then
    log_info "Pod che stanno usando GPU:"
    kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits["nvidia.com/gpu"]) | "  \(.metadata.namespace)/\(.metadata.name) - GPU: \(.spec.containers[0].resources.limits["nvidia.com/gpu"])"'
fi

echo ""

# Test 7: Create GPU Deployment for Liqo Offloading (if peering exists)
if [ "$FOREIGN_CLUSTERS" -gt 0 ] && [ "$VIRTUAL_NODES" -gt 0 ]; then
    log_info "Test 7: Test offloading GPU workload"
    echo ""
    
    # Enable offloading on namespace
    log_info "Abilitando offloading su namespace liqo-demo..."
    liqoctl offload namespace liqo-demo --namespace-mapping-strategy EnforceSameName || log_warning "Offloading già abilitato o errore"
    
    # Create GPU deployment
    cat > /tmp/test-gpu-deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-workload-test
  namespace: liqo-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gpu-workload
  template:
    metadata:
      labels:
        app: gpu-workload
    spec:
      containers:
      - name: gpu-container
        image: nvidia/cuda:12.0.0-base-ubuntu22.04
        command:
          - /bin/bash
          - -c
          - |
            while true; do
              echo "=== GPU Status on $(hostname) at $(date) ==="
              nvidia-smi --query-gpu=name,utilization.gpu,memory.used,memory.total --format=csv,noheader
              sleep 30
            done
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "1Gi"
          requests:
            cpu: "500m"
            memory: "512Mi"
EOF
    
    log_info "Deploying GPU workload for offloading test..."
    kubectl apply -f /tmp/test-gpu-deployment.yaml
    
    log_info "Waiting for pods to be scheduled (30s)..."
    sleep 30
    
    log_info "Pod distribution:"
    kubectl get pods -n liqo-demo -l app=gpu-workload -o wide
    
    # Check if any pod is on virtual node
    PODS_ON_VIRTUAL=$(kubectl get pods -n liqo-demo -l app=gpu-workload -o json | jq -r '.items[] | select(.spec.nodeName | contains("liqo")) | .metadata.name' | wc -l)
    
    if [ "$PODS_ON_VIRTUAL" -gt 0 ]; then
        log_success "GPU workload offloading funzionante! $PODS_ON_VIRTUAL pod su virtual node"
    else
        log_info "Tutti i pod sono sul nodo locale (potrebbe essere normale se il cluster remoto non ha GPU)"
    fi
    
else
    log_info "Test 7: Skip (nessun peering attivo)"
    log_info "Per testare offloading GPU:"
    echo "  1. Configura peering con un altro cluster"
    echo "  2. Verifica che il cluster remoto abbia GPU"
    echo "  3. Esegui questo script di nuovo"
fi

echo ""

# Test 8: Genera report configurazione GPU
log_info "Test 8: Report configurazione GPU"
echo ""

cat > /opt/liqo-demo/gpu-liqo-report.txt <<EOF
===========================================
  LIQO GPU CONFIGURATION REPORT
===========================================
Data: $(date)
Cluster: $(kubectl config current-context)

NODI LOCALI:
$(kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu,STATUS:.status.conditions[-1].type --no-headers)

VIRTUAL NODES (Liqo):
$(kubectl get nodes -l liqo.io/type=virtual-node -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu --no-headers 2>/dev/null || echo "Nessun virtual node")

GPU DEVICE PLUGIN:
$(kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName --no-headers 2>/dev/null || echo "Non installato")

FOREIGN CLUSTERS:
$(kubectl get foreignclusters --no-headers 2>/dev/null || echo "Nessuno")

POD CON GPU ALLOCATE:
$(kubectl get pods -A -o json | jq -r '.items[] | select(.spec.containers[].resources.limits["nvidia.com/gpu"]) | "\(.metadata.namespace)/\(.metadata.name) - Node: \(.spec.nodeName)"' 2>/dev/null || echo "Nessuno")

NAMESPACE CON OFFLOADING ABILITATO:
$(kubectl get namespaces -l liqo.io/scheduling-enabled=true -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null || echo "Nessuno")

GPU HARDWARE:
$(nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv 2>/dev/null || echo "nvidia-smi non disponibile")
EOF

log_success "Report salvato in: /opt/liqo-demo/gpu-liqo-report.txt"
cat /opt/liqo-demo/gpu-liqo-report.txt

echo ""

# Summary
log_info "=========================================="
if [ $FAILED_TESTS -eq 0 ]; then
    log_success "TUTTI I TEST SUPERATI! ✓"
    log_success "Le GPU sono correttamente esposte e configurate"
else
    log_warning "ALCUNI TEST FALLITI: $FAILED_TESTS"
    log_info "Verifica i messaggi di errore sopra"
fi
log_info "=========================================="

echo ""
log_info "File generati:"
echo "  - /opt/liqo-demo/gpu-liqo-report.txt"
echo "  - /tmp/test-gpu-pod.yaml"
echo "  - /tmp/test-gpu-deployment.yaml"

echo ""
log_info "Comandi utili:"
echo "  kubectl get nodes -o json | jq '.items[].status.capacity'"
echo "  kubectl get pods -A -o json | jq '.items[] | select(.spec.containers[].resources.limits[\"nvidia.com/gpu\"])'"
echo "  liqoctl status"
echo "  nvidia-smi"

# Cleanup test pod
log_info ""
log_info "Vuoi eliminare il pod di test? (y/n)"
read -t 10 -n 1 -r CLEANUP 2>/dev/null || CLEANUP="n"
echo ""

if [[ $CLEANUP =~ ^[Yy]$ ]]; then
    kubectl delete pod gpu-test-liqo -n liqo-demo 2>/dev/null || true
    log_info "Pod di test eliminato"
else
    log_info "Pod di test mantenuto per analisi"
fi

exit $FAILED_TESTS
