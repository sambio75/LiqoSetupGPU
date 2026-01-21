#!/bin/bash
#
# bootstrap.sh - Script di Bootstrap per Setup Demo Liqo
# Scarica e prepara tutti gli script necessari
#
# Uso rapido:
#   wget -O - https://your-repo/bootstrap.sh | sudo bash
#
# Oppure:
#   curl -fsSL https://your-repo/bootstrap.sh | sudo bash
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

print_banner() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   Liqo Demo Setup - Bootstrap Script  ║"
    echo "║   ArubaCloud GPU Server                ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Questo script deve essere eseguito come root"
        log_info "Uso: sudo $0"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        log_error "Sistema operativo non riconosciuto"
        exit 1
    fi
    
    . /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "Questo script supporta solo Ubuntu"
        log_info "Sistema rilevato: $ID"
        exit 1
    fi
    
    log_success "Sistema rilevato: Ubuntu $VERSION_ID"
}

install_dependencies() {
    log_info "Installazione dipendenze base..."
    
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -qq -y \
        curl \
        wget \
        git \
        tar \
        gzip \
        ca-certificates \
        > /dev/null 2>&1
    
    log_success "Dipendenze installate"
}

# Opzione 1: Download da GitHub (se pubblicato)
download_from_github() {
    local REPO_URL="$1"
    local TEMP_DIR="/tmp/liqo-demo-setup-$$"
    
    log_info "Download scripts da GitHub..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Clone repository
    git clone "$REPO_URL" . || {
        log_error "Impossibile clonare repository"
        return 1
    }
    
    log_success "Scripts scaricati"
    echo "$TEMP_DIR"
}

# Opzione 2: Download da URL diretto
download_from_url() {
    local ARCHIVE_URL="$1"
    local TEMP_DIR="/tmp/liqo-demo-setup-$$"
    
    log_info "Download scripts da URL..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Download archive
    wget -q "$ARCHIVE_URL" -O scripts.tar.gz || {
        log_error "Download fallito"
        return 1
    }
    
    # Extract
    tar -xzf scripts.tar.gz
    rm scripts.tar.gz
    
    log_success "Scripts estratti"
    echo "$TEMP_DIR"
}

# Opzione 3: Scripts embedded (self-contained)
create_scripts_locally() {
    local SETUP_DIR="/opt/liqo-demo-setup"
    
    log_info "Creazione directory setup: $SETUP_DIR"
    
    mkdir -p "$SETUP_DIR"
    cd "$SETUP_DIR"
    
    log_warning "ATTENZIONE: Modalità embedded non disponibile in questo bootstrap"
    log_info "Per usare gli scripts, devi:"
    echo "  1. Scaricare manualmente gli scripts"
    echo "  2. Copiarli su questo server"
    echo "  3. Eseguire ./00-main-setup.sh"
    echo ""
    log_info "Oppure modifica questo script con URL valido"
    
    return 1
}

setup_scripts() {
    local SOURCE_DIR="$1"
    local TARGET_DIR="/opt/liqo-demo-setup"
    
    log_info "Installazione scripts in: $TARGET_DIR"
    
    # Create target directory
    mkdir -p "$TARGET_DIR"
    
    # Copy scripts
    cp "$SOURCE_DIR"/*.sh "$TARGET_DIR/" 2>/dev/null || {
        log_error "Nessuno script .sh trovato"
        return 1
    }
    
    # Copy README and docs
    cp "$SOURCE_DIR"/*.md "$TARGET_DIR/" 2>/dev/null || true
    
    # Make scripts executable
    chmod +x "$TARGET_DIR"/*.sh
    
    log_success "Scripts installati in: $TARGET_DIR"
    
    # List installed scripts
    log_info "Scripts disponibili:"
    ls -lh "$TARGET_DIR"/*.sh | awk '{print "  " $9}' | sed "s|$TARGET_DIR/||"
    
    echo "$TARGET_DIR"
}

show_next_steps() {
    local SETUP_DIR="$1"
    
    echo ""
    log_success "════════════════════════════════════════"
    log_success "  Bootstrap completato con successo!"
    log_success "════════════════════════════════════════"
    echo ""
    log_info "Directory setup: $SETUP_DIR"
    echo ""
    log_info "PROSSIMI PASSI:"
    echo ""
    echo "1. Vai nella directory:"
    echo "   cd $SETUP_DIR"
    echo ""
    echo "2. (Opzionale) Leggi la documentazione:"
    echo "   cat README.md"
    echo ""
    echo "3. Avvia l'installazione completa:"
    echo "   ./00-main-setup.sh"
    echo ""
    echo "4. Oppure esegui gli script singolarmente:"
    echo "   ./01-system-prep.sh"
    echo "   ./02-nvidia-setup.sh"
    echo "   ./03-docker-setup.sh"
    echo "   ./04-k3s-setup.sh"
    echo "   ./05-liqo-setup.sh"
    echo "   ./06-verify-setup.sh"
    echo ""
    log_warning "NOTA: Se hai una GPU NVIDIA, sarà necessario un riavvio"
    log_warning "      dopo l'installazione dei driver."
    echo ""
}

interactive_mode() {
    echo ""
    log_info "Modalità interattiva"
    echo ""
    echo "Come vuoi ottenere gli scripts?"
    echo ""
    echo "1) Download da GitHub (fornisci URL repository)"
    echo "2) Download da URL diretto (fornisci URL .tar.gz)"
    echo "3) Scripts già presenti localmente (fornisci path)"
    echo "4) Esci"
    echo ""
    
    read -p "Scegli opzione (1-4): " choice
    
    case $choice in
        1)
            read -p "URL GitHub repository: " repo_url
            SOURCE_DIR=$(download_from_github "$repo_url")
            ;;
        2)
            read -p "URL archivio .tar.gz: " archive_url
            SOURCE_DIR=$(download_from_url "$archive_url")
            ;;
        3)
            read -p "Path directory locale: " local_path
            if [ ! -d "$local_path" ]; then
                log_error "Directory non trovata: $local_path"
                exit 1
            fi
            SOURCE_DIR="$local_path"
            ;;
        4)
            log_info "Uscita."
            exit 0
            ;;
        *)
            log_error "Opzione non valida"
            exit 1
            ;;
    esac
    
    if [ -z "$SOURCE_DIR" ] || [ ! -d "$SOURCE_DIR" ]; then
        log_error "Impossibile ottenere gli scripts"
        exit 1
    fi
    
    SETUP_DIR=$(setup_scripts "$SOURCE_DIR")
    show_next_steps "$SETUP_DIR"
}

auto_mode() {
    # Questo è un esempio - modifica con i tuoi URL
    local DEFAULT_REPO="https://github.com/your-username/liqo-demo-setup.git"
    local DEFAULT_URL="https://your-server.com/liqo-demo-scripts.tar.gz"
    
    log_info "Modalità automatica"
    log_warning "URL default non configurato"
    echo ""
    log_info "Per usare la modalità automatica, modifica questo script"
    log_info "e inserisci URL validi per:"
    echo "  - GitHub repository"
    echo "  - Direct download URL (.tar.gz)"
    echo ""
    log_info "Passaggio a modalità interattiva..."
    sleep 2
    
    interactive_mode
}

main() {
    print_banner
    check_root
    check_os
    install_dependencies
    
    # Check if URL provided as argument
    if [ -n "$1" ]; then
        if [[ "$1" =~ \.git$ ]]; then
            SOURCE_DIR=$(download_from_github "$1")
        elif [[ "$1" =~ \.tar\.gz$ ]]; then
            SOURCE_DIR=$(download_from_url "$1")
        elif [ -d "$1" ]; then
            SOURCE_DIR="$1"
        else
            log_error "Argomento non valido: $1"
            log_info "Uso: $0 [URL_REPO|URL_ARCHIVE|LOCAL_PATH]"
            exit 1
        fi
        
        SETUP_DIR=$(setup_scripts "$SOURCE_DIR")
        show_next_steps "$SETUP_DIR"
    else
        # No argument, try auto or interactive
        auto_mode
    fi
}

# Trap errors
trap 'log_error "Script terminato con errore"' ERR

# Run
main "$@"
