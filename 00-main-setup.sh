#!/bin/bash
#
# Script Principale per Setup Demo Liqo su Server GPU ArubaCloud
# Versione: 1.0
# Requisiti: Ubuntu 22.04/24.04 appena installato
#
# Questo script orchestra l'installazione completa di:
# - Preparazione sistema base
# - NVIDIA Container Runtime (per GPU)
# - Kubernetes (K3s) con containerd
# - Liqo
# - Test finali (GPU + Liqo)
#
# Uso: sudo ./00-main-setup.sh
#

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
print_banner() {
    echo "=========================================="
    echo "  Setup Demo Liqo - Server GPU ArubaCloud"
    echo "=========================================="
    echo ""
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root (sudo)"
        exit 1
    fi
}

# Detect Ubuntu version
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        log_info "Sistema operativo rilevato: $OS $VER"
        
        if [[ "$OS" != "ubuntu" ]]; then
            log_error "Questo script supporta solo Ubuntu"
            exit 1
        fi
        
        if [[ "$VER" != "22.04" && "$VER" != "24.04" ]]; then
            log_warning "Versione Ubuntu non testata: $VER (consigliato: 22.04 o 24.04)"
            read -p "Vuoi continuare comunque? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        log_error "Impossibile determinare il sistema operativo"
        exit 1
    fi
}

# Check GPU presence
check_gpu() {
    log_info "Verifica presenza GPU NVIDIA..."
    if command -v nvidia-smi &> /dev/null; then
        log_success "GPU NVIDIA rilevata:"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    elif lspci | grep -i nvidia &> /dev/null; then
        log_warning "GPU NVIDIA rilevata ma driver non installati"
        log_info "I driver NVIDIA verranno installati durante il setup"
    else
        log_warning "Nessuna GPU NVIDIA rilevata. Continuando senza supporto GPU..."
        export SKIP_GPU=true
    fi
}

# Create working directory
setup_workspace() {
    WORK_DIR="/opt/liqo-demo"
    log_info "Creazione directory di lavoro: $WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
    log_success "Directory creata: $WORK_DIR"
}

# Save configuration
save_config() {
    cat > "$WORK_DIR/demo-config.env" <<EOF
# Configurazione Demo Liqo
# Generato: $(date)

OS_VERSION=$VER
SKIP_GPU=${SKIP_GPU:-false}
INSTALL_DATE=$(date +%Y-%m-%d)
WORK_DIR=$WORK_DIR

# Kubernetes
K3S_VERSION=v1.28.5+k3s1
CLUSTER_NAME=demo-cluster

# Liqo
LIQO_VERSION=v0.10.3

# Networking
POD_CIDR=10.42.0.0/16
SERVICE_CIDR=10.43.0.0/16
EOF
    log_success "Configurazione salvata in: $WORK_DIR/demo-config.env"
}

# Execute subscripts
run_subscript() {
    local script=$1
    local description=$2
    
    echo ""
    log_info "=========================================="
    log_info "Esecuzione: $description"
    log_info "=========================================="
    
    if [ -f "$script" ]; then
        bash "$script"
        if [ $? -eq 0 ]; then
            log_success "$description completato"
        else
            log_error "$description fallito"
            exit 1
        fi
    else
        log_error "Script non trovato: $script"
        exit 1
    fi
}

# Main execution
main() {
    print_banner
    check_root
    detect_os
    check_gpu
    setup_workspace
    save_config
    
    # Copia configurazione per gli altri script
    export WORK_DIR
    export SKIP_GPU
    
    log_info "Inizio installazione componenti..."
    echo ""
    
    # Step 1: System preparation
    run_subscript "./01-system-prep.sh" "Preparazione sistema base"
    
    # Step 2: NVIDIA drivers and runtime (if GPU present)
    if [ "${SKIP_GPU:-false}" != "true" ]; then
        run_subscript "./02-nvidia-setup.sh" "Installazione NVIDIA drivers e runtime"
    else
        log_info "Skip installazione GPU (nessuna GPU rilevata)"
    fi
    
    # Step 3: Kubernetes (K3s) installation
    run_subscript "./03-k3s-setup.sh" "Installazione Kubernetes (K3s)"
    
    # Step 4: Liqo installation
    run_subscript "./04-liqo-setup.sh" "Installazione Liqo"
    
    # Step 5: Final tests
    run_subscript "./05-final-tests.sh" "Test finali - Kubernetes GPU e Liqo"
    
    echo ""
    log_success "=========================================="
    log_success "  INSTALLAZIONE COMPLETATA CON SUCCESSO!"
    log_success "=========================================="
    echo ""
    log_info "Directory di lavoro: $WORK_DIR"
    log_info "File di configurazione: $WORK_DIR/demo-config.env"
    log_info "Log completi disponibili in: /var/log/liqo-demo-setup.log"
    echo ""
    log_success "TEST ESEGUITI:"
    echo ""
    log_info "✓ Kubernetes funzionante con kubectl"
    if [ "${SKIP_GPU:-false}" != "true" ]; then
        log_info "✓ GPU accessibile da Kubernetes"
        echo "  Test GPU completato - vedi: $WORK_DIR/gpu-k8s-test-result.log"
    fi
    log_info "✓ Liqo installato e funzionante"
    echo "  Test Liqo completato - vedi: $WORK_DIR/liqo-test-result.log"
    echo ""
    log_info "Per vedere i risultati dei test:"
    echo "  cat $WORK_DIR/gpu-k8s-test-result.log"
    echo "  cat $WORK_DIR/liqo-test-result.log"
    echo ""
}

# Trap errors
trap 'log_error "Script terminato con errore alla riga $LINENO"' ERR

# Start
main "$@" 2>&1 | tee -a /var/log/liqo-demo-setup.log
