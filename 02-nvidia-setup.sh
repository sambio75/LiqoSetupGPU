#!/bin/bash
#
# 02-nvidia-setup.sh - Installazione NVIDIA drivers e Container Runtime
# Installa i driver NVIDIA e il NVIDIA Container Toolkit per supporto GPU in Kubernetes
#

set -e

# Colori
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

log_info "Installazione NVIDIA drivers e Container Runtime..."

# Check if GPU is present
if ! lspci | grep -i nvidia &> /dev/null; then
    log_warning "Nessuna GPU NVIDIA rilevata. Skip installazione."
    exit 0
fi

# Check if drivers are already installed
if command -v nvidia-smi &> /dev/null; then
    log_info "Driver NVIDIA già installati:"
    nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
    read -p "Vuoi reinstallare i driver? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Skip installazione driver NVIDIA"
    else
        REINSTALL_DRIVERS=true
    fi
fi

# Install NVIDIA drivers
if [ "${REINSTALL_DRIVERS:-false}" == "true" ] || ! command -v nvidia-smi &> /dev/null; then
    log_info "Installazione driver NVIDIA..."
    
    # Add NVIDIA PPA
    add-apt-repository -y ppa:graphics-drivers/ppa
    apt-get update
    
    # Detect recommended driver
    log_info "Rilevamento driver consigliato..."
    ubuntu-drivers devices
    
    # Install recommended driver
    log_info "Installazione driver consigliato..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y ubuntu-drivers-common
    ubuntu-drivers autoinstall
    
    log_success "Driver NVIDIA installati. Richiesto riavvio dopo l'installazione completa."
fi

# Verify driver installation
if command -v nvidia-smi &> /dev/null; then
    log_success "Driver NVIDIA verificati:"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
else
    log_warning "Driver NVIDIA non ancora disponibili (potrebbe richiedere riavvio)"
fi

# Install NVIDIA Container Toolkit
log_info "Installazione NVIDIA Container Toolkit..."

# Setup repository
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update

# Install toolkit
log_info "Installazione nvidia-container-toolkit..."
DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit

# Configure Docker runtime (will be configured after Docker installation)
log_info "Configurazione NVIDIA runtime per Docker..."
nvidia-ctk runtime configure --runtime=docker --set-as-default

log_success "NVIDIA Container Toolkit installato!"

# Create verification script
cat > /opt/liqo-demo/verify-gpu.sh <<'EOF'
#!/bin/bash
echo "=== Verifica GPU NVIDIA ==="
echo ""
echo "1. Driver NVIDIA:"
nvidia-smi
echo ""
echo "2. NVIDIA Container Toolkit:"
nvidia-ctk --version
echo ""
echo "3. Test container GPU:"
docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi 2>/dev/null || echo "Docker non ancora configurato o container non disponibile"
EOF

chmod +x /opt/liqo-demo/verify-gpu.sh

log_success "Script di verifica GPU creato: /opt/liqo-demo/verify-gpu.sh"
log_info "Esegui './verify-gpu.sh' dopo il riavvio per verificare l'installazione"

# Save GPU info
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.total,compute_cap --format=csv > /opt/liqo-demo/gpu-info.txt
    log_info "Informazioni GPU salvate in: /opt/liqo-demo/gpu-info.txt"
fi

log_success "Installazione NVIDIA completata!"
log_warning "IMPORTANTE: È necessario riavviare il sistema per attivare i driver NVIDIA"
log_info "Dopo il riavvio, verifica l'installazione con: nvidia-smi"
