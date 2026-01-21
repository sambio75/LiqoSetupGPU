# Setup Demo Liqo su Server GPU ArubaCloud

## 📋 Panoramica

Questi script automatizzano la preparazione completa di un server GPU Ubuntu per demo di **Liqo**, installando:

- ✅ Sistema base ottimizzato per Kubernetes
- ✅ Driver NVIDIA e Container Runtime (per GPU)
- ✅ Kubernetes (K3s) con containerd
- ✅ Liqo per multi-cluster orchestration
- ✅ Test automatici (Kubernetes + GPU + Liqo)

**NOTA:** Docker non è necessario - K3s usa containerd nativamente!

## 🚀 Quick Start

### Prerequisiti

- Server ArubaCloud con GPU NVIDIA
- Ubuntu 22.04 o 24.04 appena installato
- Accesso root/sudo
- Connessione internet

### Installazione Completa (Un Solo Comando)

```bash
# 1. Scarica gli script
cd /tmp
curl -O https://your-repo/liqo-demo-scripts.tar.gz
tar -xzf liqo-demo-scripts.tar.gz
cd liqo-demo-scripts

# 2. Rendi gli script eseguibili
chmod +x *.sh

# 3. Esegui l'installazione completa
sudo ./00-main-setup.sh
```

Lo script principale orchestrerà automaticamente tutti i passaggi.

### Installazione Manuale (Step by Step)

Se preferisci maggiore controllo o debug:

```bash
# 1. Sistema base
sudo ./01-system-prep.sh

# 2. GPU e NVIDIA (se hai GPU)
sudo ./02-nvidia-setup.sh

# 3. Docker
sudo ./03-docker-setup.sh

# 4. Kubernetes (K3s)
sudo ./04-k3s-setup.sh

# 5. Liqo
sudo ./05-liqo-setup.sh

# 6. Verifica finale
sudo ./06-verify-setup.sh
```

## 📦 Struttura Script

### `00-main-setup.sh` - Script Principale
- Orchestratore che esegue tutti gli script in sequenza
- Gestisce logging centralizzato
- Verifica prerequisiti
- Salva configurazione

**Uso:**
```bash
sudo ./00-main-setup.sh
```

### `01-system-prep.sh` - Preparazione Sistema
Cosa fa:
- Aggiorna sistema e pacchetti
- Installa tool essenziali
- Disabilita swap (required per K8s)
- Configura kernel modules e sysctl
- Setup firewall, NTP, system limits

**Output:** Sistema pronto per Kubernetes

### `02-nvidia-setup.sh` - Setup GPU
Cosa fa:
- Rileva GPU NVIDIA
- Installa driver NVIDIA più recenti
- Installa NVIDIA Container Toolkit
- Configura runtime per containerd

**Output:** GPU pronta per Kubernetes

**Note:** Richiede riavvio per attivare i driver

### `03-k3s-setup.sh` - Kubernetes
Cosa fa:
- Installa K3s (Kubernetes lightweight)
- Configura containerd per GPU
- Installa NVIDIA Device Plugin (se GPU)
- Setup kubectl e bash completion
- Crea namespace demo

**Output:** Cluster K8s funzionante con GPU

### `04-liqo-setup.sh` - Liqo Installation
Cosa fa:
- Installa liqoctl CLI
- Deploy Liqo sul cluster
- Configura peering capability
- Crea script helper e esempi

**Output:** Liqo pronto per multi-cluster

### `05-final-tests.sh` - Test Finali
Cosa fa:
- **TEST 1:** Verifica Kubernetes funzionante
- **TEST 2:** Test pratico GPU su Kubernetes (se presente)
- **TEST 3:** Verifica Liqo disponibile
- Genera report con risultati

**Output:** Report test con esempi pratici

## 📂 File e Directory Generate

Dopo l'installazione troverai:

```
/opt/liqo-demo/
├── demo-config.env              # Configurazione demo
├── installation-report.txt      # Report installazione
├── README-LIQO.md              # Documentazione Liqo
├── QUICK-START.md              # Guida rapida
│
├── k8s-info.sh                 # Info cluster Kubernetes
├── liqo-info.sh                # Info stato Liqo
├── verify-gpu.sh               # Test GPU
├── test-docker.sh              # Test Docker
│
├── test-deployment.yaml        # Deploy test K8s
├── test-gpu-pod.yaml          # Pod test GPU
├── liqo-offload-example.yaml  # Esempio offloading
│
├── liqo-peer-example.sh       # Esempio peering
└── liqo-enable-offload.sh     # Helper offloading

/var/log/
└── liqo-demo-setup.log         # Log installazione completo
```

## 🔍 Verifica Post-Installazione

### Verifica Automatica (Inclusa nell'installazione)
```bash
# I test vengono eseguiti automaticamente al termine
# Risultati salvati in:
cat /opt/liqo-demo/gpu-k8s-test-result.log    # Test GPU
cat /opt/liqo-demo/liqo-test-result.log       # Test Liqo
cat /opt/liqo-demo/quick-reference.txt        # Quick reference
```

### Test Manuali

**Kubernetes:**
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
kubectl get pods -A
```

**GPU (se presente):**
```bash
nvidia-smi
kubectl get nodes -o json | jq '.items[].status.capacity["nvidia.com/gpu"]'

# Test pratico
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.0.0-base-ubuntu22.04 \
  --limits=nvidia.com/gpu=1 \
  -- nvidia-smi
```

**Liqo:**
```bash
liqoctl version
liqoctl status
kubectl get pods -n liqo-system
```

## 🎯 Test Funzionalità

### Test Base Kubernetes
```bash
# Deploy applicazione test
kubectl apply -f /opt/liqo-demo/test-deployment.yaml

# Verifica
kubectl get pods -n liqo-demo
kubectl get svc -n liqo-demo
```

### Test GPU (se disponibile)
```bash
# Deploy pod con GPU
kubectl apply -f /opt/liqo-demo/test-gpu-pod.yaml

# Verifica log
kubectl logs -n liqo-demo gpu-test
```

### Test Liqo (richiede secondo cluster)
```bash
# Vedi: /opt/liqo-demo/README-LIQO.md
# Vedi: /opt/liqo-demo/QUICK-START.md
```

## 🔧 Troubleshooting

### Script fallisce durante l'installazione

**Sintomo:** Errore in uno degli step

**Soluzione:**
```bash
# Verifica log
tail -100 /var/log/liqo-demo-setup.log

# Riprova script specifico
sudo ./0X-nome-script.sh
```

### GPU non rilevata dopo installazione

**Sintomo:** `nvidia-smi` non funziona

**Soluzione:**
```bash
# I driver GPU richiedono riavvio
sudo reboot

# Dopo il riavvio
nvidia-smi
/opt/liqo-demo/verify-gpu.sh
```

### Kubernetes pods non partono

**Sintomo:** Pod in stato Pending/CrashLoop

**Soluzione:**
```bash
# Verifica nodes
kubectl get nodes

# Verifica pods
kubectl get pods -A
kubectl describe pod <pod-name> -n <namespace>

# Restart K3s
sudo systemctl restart k3s
```

### Docker non funziona

**Sintomo:** `docker ps` da errore

**Soluzione:**
```bash
# Verifica service
sudo systemctl status docker

# Restart Docker
sudo systemctl restart docker

# Test
docker run hello-world
```

### Liqo pods non running

**Sintomo:** Pods in liqo-system non Ready

**Soluzione:**
```bash
# Verifica stato
kubectl get pods -n liqo-system

# Log dei pod problematici
kubectl logs -n liqo-system <pod-name>

# Reinstalla Liqo
liqoctl uninstall
sudo ./05-liqo-setup.sh
```

## 📊 Tempi di Installazione

Tempo stimato per installazione completa:

| Componente | Tempo | Note |
|------------|-------|------|
| Sistema base | 5-10 min | Dipende da update |
| NVIDIA setup | 5-15 min | Prima installazione |
| K3s + containerd | 5-10 min | Include setup cluster |
| Liqo | 3-5 min | - |
| Test finali | 2-3 min | Test GPU + Liqo |
| **TOTALE** | **20-43 min** | + riavvio se GPU |

## 🎓 Cosa Imparerai

Questi script ti mostrano:

1. **Best practices Kubernetes setup**
   - Kernel tuning
   - Network configuration
   - Resource management

2. **GPU integration in K8s**
   - NVIDIA driver installation
   - Container runtime configuration
   - Device plugin deployment

3. **Liqo multi-cluster**
   - Cluster peering
   - Resource offloading
   - Cross-cluster networking

4. **Production-ready setup**
   - Security (firewall, limits)
   - Logging e monitoring
   - Automation e IaC

## 🔗 Link Utili

### Documentazione
- [Liqo Official Docs](https://docs.liqo.io)
- [K3s Documentation](https://docs.k3s.io)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/overview.html)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

### Repository
- [Liqo GitHub](https://github.com/liqotech/liqo)
- [K3s GitHub](https://github.com/k3s-io/k3s)

### ArubaCloud
- [ArubaCloud GPU Servers](https://www.cloud.it/gpu-computing.aspx)
- [Documentazione ArubaCloud](https://kb.cloud.it/)

## 📝 Note Importanti

### Sicurezza
- Gli script configurano un firewall base (UFW)
- Modifica le regole in `/etc/ufw/` per ambienti production
- Cambia le password di default
- Configura TLS/SSL per production

### Performance
- K3s è ottimizzato per risorse limitate
- Per production considera tuning aggiuntivo
- Monitora resource usage

### Networking
- Gli script usano Flannel (default K3s)
- Per setup complessi considera Calico/Cilium
- Configura networking per peering Liqo

### GPU
- Driver NVIDIA richiedono **riavvio**
- Verifica compatibilità GPU/driver
- Per multi-GPU configura device plugin

## 🤝 Contributi

Hai miglioramenti o fix? Pull request benvenute!

### Struttura suggerita per contributi:
```bash
# 1. Fork del repo
# 2. Crea branch
git checkout -b feature/miglioramento

# 3. Modifica script
# 4. Testa su Ubuntu fresh
# 5. Commit e push
git commit -m "feat: aggiunto supporto per X"
git push origin feature/miglioramento

# 6. Apri Pull Request
```

## 📄 Licenza

MIT License - Usa liberamente!

## ✍️ Autore

Scripts per demo Liqo su server GPU ArubaCloud

---

**Buona Demo! 🚀**

Per domande o problemi apri una issue su GitHub o consulta la documentazione ufficiale di Liqo.
