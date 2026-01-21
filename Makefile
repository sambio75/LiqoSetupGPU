.PHONY: help install install-step clean verify test uninstall reboot status logs

# Colori per output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Directories
INSTALL_DIR := /opt/liqo-demo
LOG_FILE := /var/log/liqo-demo-setup.log
KUBECONFIG := /etc/rancher/k3s/k3s.yaml

help: ## Mostra questo help
	@echo "$(BLUE)Liqo Demo Setup - Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Comandi disponibili:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

check-root: ## Verifica permessi root
	@if [ "$$(id -u)" != "0" ]; then \
		echo "$(YELLOW)Devi eseguire come root (usa sudo make ...)$(NC)"; \
		exit 1; \
	fi

install: check-root ## Installazione completa (tutti i componenti)
	@echo "$(BLUE)Avvio installazione completa...$(NC)"
	@chmod +x *.sh
	@./00-main-setup.sh

install-step: check-root ## Installazione step-by-step interattiva
	@echo "$(BLUE)Installazione step-by-step$(NC)"
	@echo ""
	@echo "Esegui gli script in ordine:"
	@echo "  1) make system-prep"
	@echo "  2) make nvidia-setup"
	@echo "  3) make k3s-setup"
	@echo "  4) make liqo-setup"
	@echo "  5) make final-tests"
	@echo ""

system-prep: check-root ## Step 1: Prepara sistema base
	@echo "$(BLUE)[1/5] Preparazione sistema...$(NC)"
	@./01-system-prep.sh

nvidia-setup: check-root ## Step 2: Installa NVIDIA drivers
	@echo "$(BLUE)[2/5] Setup NVIDIA...$(NC)"
	@./02-nvidia-setup.sh

k3s-setup: check-root ## Step 3: Installa Kubernetes (K3s)
	@echo "$(BLUE)[3/5] Installazione K3s...$(NC)"
	@./03-k3s-setup.sh

liqo-setup: check-root ## Step 4: Installa Liqo
	@echo "$(BLUE)[4/5] Installazione Liqo...$(NC)"
	@./04-liqo-setup.sh

final-tests: check-root ## Step 5: Test finali
	@echo "$(BLUE)[5/5] Test finali...$(NC)"
	@./05-final-tests.sh

test: ## Test componenti (non richiede root)
	@echo "$(BLUE)Test componenti...$(NC)"
	@echo ""
	@echo "$(GREEN)Kubernetes:$(NC)"
	@export KUBECONFIG=$(KUBECONFIG) && kubectl get nodes 2>/dev/null || echo "Kubernetes non accessibile"
	@echo ""
	@echo "$(GREEN)Liqo:$(NC)"
	@liqoctl version 2>/dev/null || echo "Liqo non installato"
	@echo ""
	@echo "$(GREEN)GPU:$(NC)"
	@nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "GPU non disponibile"
	@echo ""
	@echo "$(GREEN)Risultati test automatici:$(NC)"
	@test -f $(INSTALL_DIR)/gpu-k8s-test-result.log && echo "  GPU test: $(INSTALL_DIR)/gpu-k8s-test-result.log" || echo "  GPU test: non eseguito"
	@test -f $(INSTALL_DIR)/liqo-test-result.log && echo "  Liqo test: $(INSTALL_DIR)/liqo-test-result.log" || echo "  Liqo test: non eseguito"

status: ## Mostra stato completo del sistema
	@echo "$(BLUE)═══════════════════════════════════$(NC)"
	@echo "$(BLUE)     Stato Sistema Liqo Demo$(NC)"
	@echo "$(BLUE)═══════════════════════════════════$(NC)"
	@echo ""
	@echo "$(GREEN)Sistema:$(NC)"
	@uname -a
	@echo ""
	@echo "$(GREEN)Services:$(NC)"
	@systemctl is-active containerd 2>/dev/null && echo "  ✓ containerd: Running" || echo "  ✗ containerd: Not running"
	@systemctl is-active k3s 2>/dev/null && echo "  ✓ K3s: Running" || echo "  ✗ K3s: Not running"
	@echo ""
	@echo "$(GREEN)Kubernetes:$(NC)"
	@export KUBECONFIG=$(KUBECONFIG) && kubectl get nodes -o wide 2>/dev/null || echo "  Kubernetes non accessibile"
	@echo ""
	@echo "$(GREEN)Liqo:$(NC)"
	@liqoctl status 2>/dev/null || echo "  Liqo non disponibile"
	@echo ""
	@echo "$(GREEN)Test Results:$(NC)"
	@test -f $(INSTALL_DIR)/gpu-k8s-test-result.log && echo "  ✓ GPU test eseguito" || echo "  - GPU test non eseguito"
	@test -f $(INSTALL_DIR)/liqo-test-result.log && echo "  ✓ Liqo test eseguito" || echo "  - Liqo test non eseguito"

logs: ## Mostra ultimi log installazione
	@echo "$(BLUE)Ultimi 50 log installazione:$(NC)"
	@tail -n 50 $(LOG_FILE) 2>/dev/null || echo "Log file non trovato"

logs-follow: ## Segui log in real-time
	@echo "$(BLUE)Seguendo log installazione... (Ctrl+C per uscire)$(NC)"
	@tail -f $(LOG_FILE)

clean: check-root ## Pulisce file temporanei
	@echo "$(YELLOW)Pulizia file temporanei...$(NC)"
	@apt-get autoremove -y
	@apt-get clean
	@docker system prune -f 2>/dev/null || true
	@echo "$(GREEN)Pulizia completata$(NC)"

uninstall-liqo: check-root ## Disinstalla solo Liqo
	@echo "$(YELLOW)Disinstallazione Liqo...$(NC)"
	@liqoctl uninstall 2>/dev/null || echo "Liqo non installato"
	@kubectl delete namespace liqo-system 2>/dev/null || true
	@echo "$(GREEN)Liqo disinstallato$(NC)"

uninstall-k3s: check-root ## Disinstalla K3s
	@echo "$(YELLOW)Disinstallazione K3s...$(NC)"
	@/usr/local/bin/k3s-uninstall.sh 2>/dev/null || echo "K3s non installato"
	@echo "$(GREEN)K3s disinstallato$(NC)"

uninstall: check-root ## Disinstalla tutto (ATTENZIONE!)
	@echo "$(YELLOW)═══════════════════════════════════$(NC)"
	@echo "$(YELLOW)  ATTENZIONE: Disinstallazione completa$(NC)"
	@echo "$(YELLOW)═══════════════════════════════════$(NC)"
	@read -p "Sei sicuro? Questa operazione è irreversibile! (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		echo "Disinstallazione in corso..."; \
		make uninstall-liqo || true; \
		make uninstall-k3s || true; \
		rm -rf $(INSTALL_DIR); \
		rm -f $(LOG_FILE); \
		echo "$(GREEN)Disinstallazione completata$(NC)"; \
	else \
		echo "$(BLUE)Operazione annullata$(NC)"; \
	fi

reboot: check-root ## Riavvia il sistema
	@echo "$(YELLOW)Il sistema si riavvierà tra 5 secondi...$(NC)"
	@echo "$(YELLOW)Premi Ctrl+C per annullare$(NC)"
	@sleep 5
	@reboot

info: ## Mostra informazioni installazione
	@echo "$(BLUE)═══════════════════════════════════$(NC)"
	@echo "$(BLUE)  Informazioni Installazione$(NC)"
	@echo "$(BLUE)═══════════════════════════════════$(NC)"
	@echo ""
	@if [ -f $(INSTALL_DIR)/quick-reference.txt ]; then \
		cat $(INSTALL_DIR)/quick-reference.txt; \
	else \
		echo "$(YELLOW)Informazioni non trovate$(NC)"; \
		echo "Probabilmente l'installazione non è ancora completa"; \
		echo "Esegui: make install"; \
	fi

quick-start: ## Mostra quick start guide
	@if [ -f $(INSTALL_DIR)/QUICK-START.md ]; then \
		cat $(INSTALL_DIR)/QUICK-START.md; \
	else \
		echo "$(YELLOW)Quick start guide non trovata$(NC)"; \
		echo "Esegui prima: make install"; \
	fi

gpu-test: ## Test GPU
	@if [ -f $(INSTALL_DIR)/gpu-k8s-test-result.log ]; then \
		echo "$(GREEN)Risultati test GPU:$(NC)"; \
		cat $(INSTALL_DIR)/gpu-k8s-test-result.log; \
	else \
		echo "$(YELLOW)Test GPU non ancora eseguito. Esegui: make final-tests$(NC)"; \
	fi

liqo-test: ## Test Liqo
	@if [ -f $(INSTALL_DIR)/liqo-test-result.log ]; then \
		echo "$(GREEN)Risultati test Liqo:$(NC)"; \
		cat $(INSTALL_DIR)/liqo-test-result.log; \
	else \
		echo "$(YELLOW)Test Liqo non ancora eseguito. Esegui: make final-tests$(NC)"; \
	fi

quick-ref: ## Mostra quick reference
	@if [ -f $(INSTALL_DIR)/quick-reference.txt ]; then \
		cat $(INSTALL_DIR)/quick-reference.txt; \
	else \
		echo "$(YELLOW)Quick reference non trovata. Esegui: make install$(NC)"; \
	fi

# Shortcuts
prep: system-prep ## Alias per system-prep
gpu: nvidia-setup ## Alias per nvidia-setup
k8s: k3s-setup ## Alias per k3s-setup
liqo: liqo-setup ## Alias per liqo-setup
tests: final-tests ## Alias per final-tests

gpu-liqo-test: ## Test completo GPU con Liqo
	@echo "$(BLUE)Test GPU con Liqo...$(NC)"
	@if [ -f $(INSTALL_DIR)/test-liqo-gpu.sh ]; then \
		bash $(INSTALL_DIR)/test-liqo-gpu.sh; \
	else \
		echo "$(YELLOW)Script non trovato. Esegui prima: make liqo$(NC)"; \
	fi

all: install ## Installazione completa

# Development helpers
list-scripts: ## Lista tutti gli script
	@echo "$(BLUE)Script disponibili:$(NC)"
	@ls -1 *.sh

edit-main: ## Modifica script principale
	@${EDITOR:-nano} 00-main-setup.sh

# Default target
.DEFAULT_GOAL := help
