#!/bin/bash
#
# 01-system-prep.sh - Preparazione sistema base
# Aggiorna il sistema, installa pacchetti essenziali e configura il sistema
#

set -e

# Colori
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

log_info "Aggiornamento sistema e installazione pacchetti base..."

# Update package list
log_info "Update package repository..."
apt-get update

# Upgrade existing packages
log_info "Upgrade pacchetti esistenti..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install essential packages
log_info "Installazione pacchetti essenziali..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    vim \
    git \
    jq \
    net-tools \
    htop \
    iotop \
    iftop \
    build-essential \
    unzip \
    zip \
    tree \
    tmux \
    screen \
    bash-completion

# Disable swap (required for Kubernetes)
log_info "Disabilitazione swap (richiesto da Kubernetes)..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab
log_success "Swap disabilitato"

# Configure kernel modules
log_info "Configurazione moduli kernel per Kubernetes..."
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Configure sysctl parameters
log_info "Configurazione parametri sysctl..."
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
net.ipv6.conf.all.forwarding        = 1
EOF

sysctl --system > /dev/null

# Configure firewall (UFW)
log_info "Configurazione firewall..."
if command -v ufw &> /dev/null; then
    # Allow SSH
    ufw allow 22/tcp
    
    # Allow Kubernetes API
    ufw allow 6443/tcp
    
    # Allow Kubernetes NodePorts
    ufw allow 30000:32767/tcp
    
    # Allow flannel/weave
    ufw allow 8472/udp
    
    # Enable UFW
    ufw --force enable
    log_success "Firewall configurato"
else
    log_info "UFW non installato, skip configurazione firewall"
fi

# Set hostname if not already set
CURRENT_HOSTNAME=$(hostname)
if [[ "$CURRENT_HOSTNAME" == "localhost" ]] || [[ -z "$CURRENT_HOSTNAME" ]]; then
    NEW_HOSTNAME="liqo-demo-$(date +%s | tail -c 5)"
    log_info "Impostazione hostname: $NEW_HOSTNAME"
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "127.0.0.1 $NEW_HOSTNAME" >> /etc/hosts
fi

# Timezone configuration
log_info "Configurazione timezone (Europe/Rome)..."
timedatectl set-timezone Europe/Rome

# Install and configure NTP
log_info "Configurazione NTP per sincronizzazione orario..."
DEBIAN_FRONTEND=noninteractive apt-get install -y chrony
systemctl enable chrony
systemctl start chrony

# Increase system limits
log_info "Configurazione limiti di sistema..."
cat > /etc/security/limits.d/99-kubernetes.conf <<EOF
* soft nofile 65536
* hard nofile 65536
* soft nproc 65536
* hard nproc 65536
EOF

# Configure journal size
log_info "Configurazione dimensione journal..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-liqo.conf <<EOF
[Journal]
SystemMaxUse=1G
SystemMaxFileSize=100M
EOF
systemctl restart systemd-journald

# Clean up
log_info "Pulizia pacchetti non necessari..."
apt-get autoremove -y
apt-get clean

log_success "Preparazione sistema completata!"
log_info "Hostname: $(hostname)"
log_info "Timezone: $(timedatectl | grep 'Time zone' | awk '{print $3}')"
log_info "Swap: $(free -h | grep Swap | awk '{print $2}')"
