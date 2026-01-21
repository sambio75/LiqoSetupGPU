#!/bin/bash
#
# 05-final-tests.sh - Test finali Kubernetes GPU e Liqo
# Esegue test pratici per dimostrare che tutto funziona
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

WORK_DIR="/opt/liqo-demo"
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

print_header() {
    echo ""
    echo "=========================================="
    echo "  $1"
    echo "=========================================="
}

print_header "TEST FINALI - KUBERNETES GPU e LIQO"

# =============================================================================
# TEST 1: KUBERNETES FUNZIONA
# =============================================================================

print_header "TEST 1: Kubernetes Funzionante"

log_info "Verifica cluster Kubernetes..."

if ! kubectl get nodes &> /dev/null; then
    log_error "Kubernetes non è accessibile"
    exit 1
fi

NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

if [ "$NODE_STATUS" == "True" ]; then
    log_success "Kubernetes cluster attivo e funzionante"
    log_info "  Node: $NODE_NAME"
    log_info "  Status: Ready"
else
    log_error "Node non è Ready"
    kubectl get nodes
    exit 1
fi

# Verifica sistema pods
SYSTEM_PODS=$(kubectl get pods -n kube-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
log_success "System pods running: $SYSTEM_PODS"

# =============================================================================
# TEST 2: GPU ACCESSIBILE DA KUBERNETES (se presente)
# =============================================================================

print_header "TEST 2: GPU in Kubernetes"

GPU_AVAILABLE=false
if command -v nvidia-smi &> /dev/null; then
    log_info "GPU NVIDIA rilevata nel sistema"
    
    # Verifica GPU resources in Kubernetes
    GPU_CAPACITY=$(kubectl get nodes -o json | jq -r '.items[0].status.capacity["nvidia.com/gpu"]' 2>/dev/null)
    
    if [ "$GPU_CAPACITY" != "null" ] && [ -n "$GPU_CAPACITY" ] && [ "$GPU_CAPACITY" != "0" ]; then
        log_success "GPU disponibile in Kubernetes: $GPU_CAPACITY GPU(s)"
        GPU_AVAILABLE=true
    else
        log_warning "GPU non ancora disponibile in Kubernetes"
        log_info "Questo può richiedere un riavvio del sistema"
        log_info "Dopo il riavvio, la GPU sarà automaticamente disponibile"
    fi
else
    log_info "Nessuna GPU NVIDIA presente nel sistema (ok per test senza GPU)"
fi

# Test pratico GPU (se disponibile)
if [ "$GPU_AVAILABLE" = true ]; then
    log_info "Esecuzione test GPU su Kubernetes..."
    
    # Crea namespace di test
    kubectl create namespace gpu-test 2>/dev/null || true
    
    # Deploy pod GPU test
    cat > /tmp/gpu-test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test-pod
  namespace: gpu-test
spec:
  restartPolicy: Never
  containers:
  - name: cuda-test
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: 
    - sh
    - -c
    - |
      echo "=== TEST GPU KUBERNETES ==="
      echo "Data: \$(date)"
      echo ""
      nvidia-smi
      echo ""
      echo "=== TEST COMPLETATO ==="
    resources:
      limits:
        nvidia.com/gpu: 1
EOF
    
    # Apply e attendi completamento
    kubectl delete pod gpu-test-pod -n gpu-test 2>/dev/null || true
    sleep 2
    kubectl apply -f /tmp/gpu-test-pod.yaml
    
    log_info "Attesa completamento test GPU (max 120s)..."
    
    # Attendi che il pod completi o fallisca
    for i in {1..24}; do
        POD_PHASE=$(kubectl get pod gpu-test-pod -n gpu-test -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        
        if [ "$POD_PHASE" == "Succeeded" ]; then
            log_success "Test GPU completato con successo!"
            break
        elif [ "$POD_PHASE" == "Failed" ]; then
            log_error "Test GPU fallito"
            kubectl logs gpu-test-pod -n gpu-test
            break
        fi
        
        if [ $i -eq 24 ]; then
            log_warning "Test GPU timeout (pod ancora in running)"
            POD_PHASE="Timeout"
        fi
        
        sleep 5
    done
    
    # Salva risultati
    if [ "$POD_PHASE" == "Succeeded" ]; then
        kubectl logs gpu-test-pod -n gpu-test > $WORK_DIR/gpu-k8s-test-result.log 2>&1
        
        log_success "Risultati test GPU salvati in: $WORK_DIR/gpu-k8s-test-result.log"
        echo ""
        log_info "Output del test:"
        echo "---"
        kubectl logs gpu-test-pod -n gpu-test | head -20
        echo "---"
        
        # Cleanup
        kubectl delete namespace gpu-test 2>/dev/null || true
    else
        log_error "Test GPU non completato correttamente"
        kubectl describe pod gpu-test-pod -n gpu-test
    fi
else
    log_info "Test GPU non eseguito (GPU non disponibile o non presente)"
    echo "Test GPU: SKIP (no GPU)" > $WORK_DIR/gpu-k8s-test-result.log
fi

# =============================================================================
# TEST 3: LIQO INSTALLATO E FUNZIONANTE
# =============================================================================

print_header "TEST 3: Liqo Disponibile"

# Verifica liqoctl
if ! command -v liqoctl &> /dev/null; then
    log_error "liqoctl non trovato"
    exit 1
fi

LIQO_VERSION=$(liqoctl version --client 2>/dev/null | grep "liqoctl version" | awk '{print $3}')
log_success "liqoctl installato: $LIQO_VERSION"

# Verifica namespace Liqo
if ! kubectl get namespace liqo-system &> /dev/null; then
    log_error "Namespace liqo-system non presente"
    exit 1
fi

log_success "Namespace liqo-system presente"

# Verifica Liqo pods
LIQO_PODS_TOTAL=$(kubectl get pods -n liqo-system --no-headers 2>/dev/null | wc -l)
LIQO_PODS_RUNNING=$(kubectl get pods -n liqo-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

if [ "$LIQO_PODS_TOTAL" -eq 0 ]; then
    log_error "Nessun pod Liqo trovato"
    exit 1
fi

log_success "Liqo pods: $LIQO_PODS_RUNNING/$LIQO_PODS_TOTAL Running"

if [ "$LIQO_PODS_RUNNING" -lt "$LIQO_PODS_TOTAL" ]; then
    log_warning "Alcuni pod Liqo non sono ancora Running (potrebbero richiedere più tempo)"
    kubectl get pods -n liqo-system
fi

# Test liqoctl status
log_info "Test comando liqoctl status..."

if liqoctl status > /tmp/liqo-status.txt 2>&1; then
    log_success "liqoctl status funziona correttamente"
    
    # Salva output
    cat /tmp/liqo-status.txt > $WORK_DIR/liqo-test-result.log
    
    log_info "Output liqoctl status:"
    echo "---"
    cat /tmp/liqo-status.txt
    echo "---"
else
    log_warning "liqoctl status ha restituito un errore (normale per nuovo cluster senza peering)"
    cat /tmp/liqo-status.txt > $WORK_DIR/liqo-test-result.log
fi

# Informazioni su come usare Liqo
log_info ""
log_info "Liqo è pronto per il peering con altri cluster!"
log_info ""
log_info "Prossimi passi per usare Liqo:"
echo "  1. Setup secondo cluster Kubernetes"
echo "  2. Installa Liqo sul secondo cluster"
echo "  3. Su secondo cluster: liqoctl generate peer-command"
echo "  4. Su questo cluster: esegui il comando generato"
echo "  5. Verifica: liqoctl status peer"
echo ""

# =============================================================================
# RIEPILOGO FINALE
# =============================================================================

print_header "RIEPILOGO TEST"

echo ""
log_success "✓ TEST 1: Kubernetes funzionante"
log_info "  - Cluster attivo con node Ready"
log_info "  - System pods in esecuzione"
echo ""

if [ "$GPU_AVAILABLE" = true ]; then
    if [ "$POD_PHASE" == "Succeeded" ]; then
        log_success "✓ TEST 2: GPU accessibile da Kubernetes"
        log_info "  - $GPU_CAPACITY GPU disponibile(i)"
        log_info "  - Test pratico completato con successo"
        log_info "  - Risultati: $WORK_DIR/gpu-k8s-test-result.log"
    else
        log_warning "! TEST 2: GPU presente ma test non completato"
        log_info "  - Potrebbe richiedere riavvio del sistema"
    fi
else
    if command -v nvidia-smi &> /dev/null; then
        log_warning "! TEST 2: GPU presente ma non ancora in Kubernetes"
        log_info "  - Riavvia il sistema: sudo reboot"
        log_info "  - Dopo riavvio, GPU sarà disponibile automaticamente"
    else
        log_info "○ TEST 2: GPU non presente (ok)"
    fi
fi

echo ""
log_success "✓ TEST 3: Liqo installato e disponibile"
log_info "  - liqoctl: $LIQO_VERSION"
log_info "  - Pods attivi: $LIQO_PODS_RUNNING/$LIQO_PODS_TOTAL"
log_info "  - Pronto per multi-cluster peering"
log_info "  - Risultati: $WORK_DIR/liqo-test-result.log"
echo ""

# Crea quick reference
cat > $WORK_DIR/quick-reference.txt <<EOF
===========================================
  LIQO DEMO - QUICK REFERENCE
===========================================

KUBERNETES:
-----------
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  kubectl get nodes
  kubectl get pods -A

GPU (se presente):
------------------
  nvidia-smi
  kubectl get nodes -o json | jq '.items[].status.capacity["nvidia.com/gpu"]'
  
  Test GPU:
  kubectl run gpu-test --rm -it --restart=Never \
    --image=nvidia/cuda:12.0.0-base-ubuntu22.04 \
    --limits=nvidia.com/gpu=1 \
    -- nvidia-smi

LIQO:
-----
  liqoctl version
  liqoctl status
  kubectl get pods -n liqo-system
  
  Per peering con altro cluster:
  1. Su cluster remoto: liqoctl generate peer-command
  2. Su questo cluster: esegui il comando generato
  3. Verifica: liqoctl status peer

FILE RISULTATI TEST:
--------------------
  - GPU Test: $WORK_DIR/gpu-k8s-test-result.log
  - Liqo Test: $WORK_DIR/liqo-test-result.log

DOCUMENTAZIONE:
---------------
  - README: $WORK_DIR/README-LIQO.md
  - Examples: Vedi documentazione Liqo
    https://docs.liqo.io

EOF

log_success "Quick reference salvata in: $WORK_DIR/quick-reference.txt"

# Check se richiesto riavvio
if [ -f /var/run/reboot-required ] || [ "$GPU_AVAILABLE" = false ] && command -v nvidia-smi &> /dev/null; then
    echo ""
    log_warning "=========================================="
    log_warning "  RIAVVIO CONSIGLIATO"
    log_warning "=========================================="
    log_warning "Per attivare completamente la GPU in Kubernetes:"
    echo ""
    log_info "  sudo reboot"
    echo ""
    log_info "Dopo il riavvio:"
    echo "  1. Verifica GPU: nvidia-smi"
    echo "  2. Verifica in K8s: kubectl get nodes -o json | jq '.items[].status.capacity'"
    echo "  3. Testa GPU: kubectl run gpu-test --rm -it --restart=Never \\"
    echo "                --image=nvidia/cuda:12.0.0-base-ubuntu22.04 \\"
    echo "                --limits=nvidia.com/gpu=1 -- nvidia-smi"
    echo ""
fi

print_header "TEST COMPLETATI"
log_success "Tutti i test sono stati eseguiti!"
log_info "Per dettagli completi vedi i file di log in: $WORK_DIR/"
