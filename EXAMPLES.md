# Esempi Pratici e Scenari Demo Liqo

## 📚 Indice

1. [Setup Iniziale](#setup-iniziale)
2. [Demo Single Cluster](#demo-single-cluster)
3. [Demo Multi-Cluster](#demo-multi-cluster)
4. [GPU Workloads](#gpu-workloads)
5. [Scenari Avanzati](#scenari-avanzati)
6. [Troubleshooting Comuni](#troubleshooting-comuni)

---

## Setup Iniziale

### Scenario 1: Installazione Express (Un Solo Comando)

**Situazione:** Hai un server Ubuntu fresco e vuoi setup completo veloce.

```bash
# Download e installazione automatica
cd /tmp
git clone <your-repo-url> liqo-setup
cd liqo-setup
sudo make install

# Attendi 20-40 minuti (dipende da connessione e hardware)
# Al termine, verifica:
sudo make verify
```

**Output atteso:**
```
[✓] Sistema: Ubuntu 22.04
[✓] Docker: Installato
[✓] K3s: Running
[✓] Liqo: OK
```

### Scenario 2: Installazione Step-by-Step (Debugging)

**Situazione:** Vuoi controllare ogni step o debugging.

```bash
# Step 1: Sistema base
sudo make system-prep
# Verifica: Swap disabilitato, kernel modules caricati

# Step 2: GPU (se presente)
sudo make nvidia-setup
# Verifica: nvidia-smi funziona
# NOTA: Potrebbe richiedere riavvio!

# Riavvia se necessario
sudo reboot

# Dopo riavvio, verifica GPU
nvidia-smi

# Step 3: Docker
sudo make docker-setup
# Verifica: docker ps funziona

# Step 4: Kubernetes
sudo make k3s-setup
# Verifica: kubectl get nodes → Ready

# Step 5: Liqo
sudo make liqo-setup
# Verifica: liqoctl status → OK

# Step 6: Verifica finale
sudo make verify
```

---

## Demo Single Cluster

### Scenario 3: Deploy Applicazione Base

**Situazione:** Test cluster locale con applicazione semplice.

```bash
# Setup environment
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Deploy nginx test
kubectl create deployment nginx-demo --image=nginx:latest --replicas=3

# Esponi il service
kubectl expose deployment nginx-demo --port=80 --type=NodePort

# Verifica
kubectl get pods -l app=nginx-demo
kubectl get svc nginx-demo

# Test accesso
NODE_PORT=$(kubectl get svc nginx-demo -o jsonpath='{.spec.ports[0].nodePort}')
curl http://localhost:$NODE_PORT
```

**Output atteso:**
```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
```

### Scenario 4: Deploy con Persistence

**Situazione:** Applicazione che richiede storage persistente.

```bash
# Crea PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: demo-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# Deploy PostgreSQL con PVC
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:15
        env:
        - name: POSTGRES_PASSWORD
          value: "demopassword"
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-storage
        persistentVolumeClaim:
          claimName: demo-pvc
EOF

# Verifica
kubectl get pvc
kubectl get pods -l app=postgres
kubectl logs -l app=postgres
```

### Scenario 5: Monitoring con Metrics

**Situazione:** Vuoi visualizzare metriche del cluster.

```bash
# Installa metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch per K3s (disabilita TLS verification)
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'

# Attendi che sia ready
kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=120s

# Visualizza metriche
kubectl top nodes
kubectl top pods -A

# Dashboard semplice con K9s (opzionale)
curl -sL https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz | tar xz -C /usr/local/bin
k9s
```

---

## Demo Multi-Cluster

### Scenario 6: Setup Secondo Cluster (Cloud)

**Situazione:** Vuoi testare vero multi-cluster con GKE/EKS/AKS.

#### Su Cluster Cloud (es. GKE):

```bash
# Crea cluster GKE (esempio)
gcloud container clusters create liqo-cloud \
  --zone=europe-west1-b \
  --num-nodes=2 \
  --machine-type=n1-standard-2

# Get credentials
gcloud container clusters get-credentials liqo-cloud --zone=europe-west1-b

# Installa Liqo
liqoctl install gke --cluster-name=cloud-cluster

# Genera peer command
liqoctl generate peer-command
```

**Output:**
```bash
liqoctl peer out-of-band cloud-cluster \
  --auth-url https://XX.XX.XX.XX:XXXXX/auth \
  --cluster-token eyJhbGciOiJS...
```

#### Sul Tuo Server ArubaCloud:

```bash
# Esegui comando generato sopra
liqoctl peer out-of-band cloud-cluster \
  --auth-url https://XX.XX.XX.XX:XXXXX/auth \
  --cluster-token eyJhbGciOiJS...

# Verifica peering
liqoctl status peer
kubectl get foreignclusters

# Dovresti vedere:
# NAME            TYPE        OUTGOING PEERING   INCOMING PEERING   AGE
# cloud-cluster   OutOfBand   Established        Established        1m
```

### Scenario 7: Offloading Workload

**Situazione:** Deploy app che si distribuisce tra cluster.

```bash
# Abilita offloading su namespace
kubectl create namespace multi-demo
liqoctl offload namespace multi-demo

# Deploy applicazione distribuita
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: distributed-app
  namespace: multi-demo
spec:
  replicas: 6
  selector:
    matchLabels:
      app: distributed
  template:
    metadata:
      labels:
        app: distributed
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
---
apiVersion: v1
kind: Service
metadata:
  name: distributed-svc
  namespace: multi-demo
spec:
  selector:
    app: distributed
  ports:
  - port: 80
  type: ClusterIP
EOF

# Verifica distribuzione
kubectl get pods -n multi-demo -o wide

# Dovresti vedere pod su:
# - Nodi locali
# - Virtual nodes (cluster remoto)
```

### Scenario 8: Service Reflection

**Situazione:** Accedere a service del cluster remoto.

```bash
# Il service nel cluster remoto viene automaticamente riflesso
# Esempio: PostgreSQL su cluster remoto

# Su cluster remoto:
kubectl create deployment postgres --image=postgres:15 -n database
kubectl expose deployment postgres --port=5432 -n database

# Sul tuo cluster:
kubectl get svc -n database
# Vedrai il service "postgres" disponibile localmente

# Connettiti al database remoto
kubectl run psql-client -it --rm --image=postgres:15 -- \
  psql -h postgres.database.svc.cluster.local -U postgres
```

---

## GPU Workloads

### Scenario 9: Deploy GPU Pod

**Situazione:** Eseguire workload GPU su Kubernetes.

```bash
# Verifica GPU disponibili
kubectl get nodes -o json | jq '.items[].status.capacity["nvidia.com/gpu"]'

# Deploy pod con GPU
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
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

# Verifica output
kubectl wait --for=condition=completed pod/gpu-test --timeout=60s
kubectl logs gpu-test
```

**Output atteso:**
```
+-----------------------------------------------------------------------------+
| NVIDIA-SMI 535.xx.xx    Driver Version: 535.xx.xx    CUDA Version: 12.0   |
|-------------------------------+----------------------+----------------------+
| GPU  Name        Persistence-M| Bus-Id        Disp.A | Volatile Uncorr. ECC |
...
```

### Scenario 10: TensorFlow Training Job

**Situazione:** Training ML con GPU.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: tensorflow-gpu
spec:
  restartPolicy: Never
  containers:
  - name: tensorflow
    image: tensorflow/tensorflow:latest-gpu
    command:
      - python
      - -c
      - |
        import tensorflow as tf
        print("TensorFlow version:", tf.__version__)
        print("GPU available:", tf.config.list_physical_devices('GPU'))
        
        # Simple computation on GPU
        with tf.device('/GPU:0'):
            a = tf.constant([[1.0, 2.0], [3.0, 4.0]])
            b = tf.constant([[5.0, 6.0], [7.0, 8.0]])
            c = tf.matmul(a, b)
            print("Result:", c)
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Segui i log
kubectl logs -f tensorflow-gpu
```

### Scenario 11: PyTorch Distributed Training

**Situazione:** Training distribuito con Liqo multi-cluster.

```bash
# Crea namespace con offloading
kubectl create namespace ml-training
liqoctl offload namespace ml-training

# Deploy PyTorch training job (3 replicas distribuite)
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pytorch-training
  namespace: ml-training
spec:
  replicas: 3
  selector:
    matchLabels:
      app: pytorch
  template:
    metadata:
      labels:
        app: pytorch
    spec:
      containers:
      - name: pytorch
        image: pytorch/pytorch:latest
        command: ["sleep", "infinity"]
        resources:
          limits:
            nvidia.com/gpu: 1
            memory: "4Gi"
          requests:
            cpu: "2"
            memory: "2Gi"
EOF

# Verifica distribuzione su cluster multipli
kubectl get pods -n ml-training -o wide
```

### Scenario 12: Test Completo GPU con Liqo

**Situazione:** Verificare che le GPU siano correttamente esposte attraverso Liqo.

```bash
# Esegui test completo
/opt/liqo-demo/test-liqo-gpu.sh

# Oppure con make
make gpu-liqo-test
```

**Cosa verifica questo test:**
1. ✓ GPU disponibili sul nodo locale
2. ✓ NVIDIA Device Plugin funzionante
3. ✓ Liqo installato correttamente
4. ✓ Foreign Clusters e Virtual Nodes
5. ✓ Deploy e test di un pod GPU
6. ✓ Allocazione GPU corretta
7. ✓ Offloading GPU workload (se peering attivo)
8. ✓ Genera report configurazione completo

**Output esempio:**
```
===========================================
  LIQO GPU CONFIGURATION REPORT
===========================================
NODI LOCALI:
demo-node   1   Ready

VIRTUAL NODES (Liqo):
liqo-remote-cluster   2   

GPU DEVICE PLUGIN:
nvidia-device-plugin-ds-xxxxx   Running   demo-node

FOREIGN CLUSTERS:
remote-cluster   Established   Established

POD CON GPU ALLOCATE:
liqo-demo/gpu-workload-test-xxx - Node: liqo-remote-cluster
```

**Test manuale GPU su Virtual Node:**
```bash
# Verifica GPU su virtual nodes
kubectl get nodes -l liqo.io/type=virtual-node -o json | \
  jq '.items[] | {name: .metadata.name, gpu: .status.capacity["nvidia.com/gpu"]}'

# Deploy pod che richiede GPU
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: gpu-on-virtual
  namespace: liqo-demo
spec:
  nodeSelector:
    liqo.io/type: virtual-node
  containers:
  - name: cuda
    image: nvidia/cuda:12.0.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

# Verifica scheduling
kubectl get pod gpu-on-virtual -n liqo-demo -o wide
kubectl logs gpu-on-virtual -n liqo-demo
```

---

## Scenari Avanzati

### Scenario 13: Auto-scaling con HPA

**Situazione:** Scale automatico basato su CPU.

```bash
# Deploy applicazione
kubectl create deployment php-apache --image=registry.k8s.io/hpa-example

kubectl expose deployment php-apache --port=80 --type=ClusterIP

# Crea HPA
kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10

# Genera load
kubectl run -it --rm load-generator --image=busybox -- /bin/sh -c \
  "while sleep 0.01; do wget -q -O- http://php-apache; done"

# In altra finestra, monitora scaling
watch kubectl get hpa
watch kubectl get pods
```

### Scenario 14: Network Policies

**Situazione:** Isolare namespace per sicurezza.

```bash
# Crea namespace isolato
kubectl create namespace secure-app

# Deploy app
kubectl run app1 -n secure-app --image=nginx
kubectl run app2 -n secure-app --image=nginx

# Default: tutto comunicante
kubectl exec -n secure-app app1 -- curl http://app2 # OK

# Applica network policy (deny all)
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: secure-app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Ora bloccato
kubectl exec -n secure-app app1 -- curl http://app2 # FAIL

# Permetti specifico traffico
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-app1-to-app2
  namespace: secure-app
spec:
  podSelector:
    matchLabels:
      run: app2
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: app1
EOF

# Ora funziona di nuovo
kubectl exec -n secure-app app1 -- curl http://app2 # OK
```

### Scenario 15: Backup e Restore con Velero

**Situazione:** Backup cluster per disaster recovery.

```bash
# Installa Velero
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xzf velero-v1.12.0-linux-amd64.tar.gz
mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Configura backup (esempio: filesystem)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio:9000 \
  --use-volume-snapshots=false

# Crea backup
velero backup create demo-backup --include-namespaces liqo-demo

# Lista backup
velero backup get

# Restore (su altro cluster o dopo disaster)
velero restore create --from-backup demo-backup
```

---

## Troubleshooting Comuni

### Problema 1: Pod in Pending

**Sintomo:**
```bash
kubectl get pods
# NAME          READY   STATUS    RESTARTS   AGE
# my-pod        0/1     Pending   0          5m
```

**Diagnosi e Fix:**
```bash
# Check eventi
kubectl describe pod my-pod

# Cause comuni:
# 1. Insufficient resources
kubectl top nodes
kubectl describe node

# 2. No nodes available
kubectl get nodes

# 3. PVC not bound
kubectl get pvc

# 4. Taints/Tolerations
kubectl describe node | grep Taint
```

### Problema 2: GPU Non Rilevata

**Sintomo:** Pod GPU in pending o error.

**Fix:**
```bash
# 1. Verifica driver
nvidia-smi

# 2. Verifica device plugin
kubectl get pods -n kube-system | grep nvidia

# 3. Verifica node capacity
kubectl get nodes -o json | jq '.items[].status.capacity'

# 4. Reinstalla device plugin
kubectl delete -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.5/nvidia-device-plugin.yml

# 5. Riavvia se necessario
sudo reboot
```

### Problema 3: Liqo Peering Fallisce

**Sintomo:** Foreign cluster non in "Established".

**Fix:**
```bash
# 1. Verifica network connectivity
ping <remote-cluster-ip>

# 2. Check firewall
sudo ufw status

# 3. Verifica certificati
kubectl get secrets -n liqo-system

# 4. Log Liqo controller
kubectl logs -n liqo-system -l app.kubernetes.io/name=liqo-controller-manager

# 5. Ricrea peering
liqoctl unpeer out-of-band <cluster-name>
# Riprova peering
```

### Problema 4: Service Non Raggiungibile

**Sintomo:** Cannot connect to service.

**Fix:**
```bash
# 1. Verifica service e pods
kubectl get svc,pods -n <namespace>

# 2. Verifica endpoints
kubectl get endpoints -n <namespace>

# 3. Test interno al cluster
kubectl run test-pod --rm -it --image=busybox -- \
  wget -O- http://<service-name>.<namespace>.svc.cluster.local

# 4. Check network policies
kubectl get networkpolicies -A

# 5. Verifica DNS
kubectl run test-dns --rm -it --image=busybox -- \
  nslookup <service-name>.<namespace>.svc.cluster.local
```

---

## Tips & Best Practices

### Performance Tuning

```bash
# Limita resource usage
kubectl set resources deployment <name> \
  --limits=cpu=500m,memory=512Mi \
  --requests=cpu=250m,memory=256Mi

# Use node affinity per GPU
nodeSelector:
  nvidia.com/gpu: "true"

# Priority classes per workload critici
kubectl create priorityclass high-priority --value=1000 --global-default=false
```

### Security

```bash
# Use secrets per credenziali
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=secret

# RBAC per limitare accessi
kubectl create role pod-reader --verb=get,list --resource=pods
kubectl create rolebinding read-pods --role=pod-reader --user=user1

# Pod Security Standards
kubectl label namespace <ns> pod-security.kubernetes.io/enforce=restricted
```

### Monitoring

```bash
# Prometheus & Grafana (kube-prometheus-stack)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack

# Access Grafana
kubectl port-forward svc/monitoring-grafana 3000:80 -n default
```

---

## Risorse Aggiuntive

- [Liqo Examples GitHub](https://github.com/liqotech/liqo/tree/master/examples)
- [K3s Best Practices](https://docs.k3s.io/advanced)
- [Kubernetes Patterns](https://kubernetes.io/docs/concepts/)
- [NVIDIA GPU Operator](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html)

