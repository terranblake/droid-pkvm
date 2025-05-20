#!/bin/bash
# Script to set up Kubernetes resources after initial setup
# This script is meant to be run by the droid user

set -e
LOGFILE="$(pwd)/kubernetes-setup.log"

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

log "Running Kubernetes operations as user $(whoami)..."

# Ensure kubeconfig is set properly
export KUBECONFIG=$HOME/.kube/config
if [ ! -f "$KUBECONFIG" ]; then
    log "ERROR: Kubernetes config not found at $KUBECONFIG"
    log "Trying to copy from /etc/rancher/k3s/k3s.yaml..."
    mkdir -p $(dirname $KUBECONFIG)
    sudo cp /etc/rancher/k3s/k3s.yaml $KUBECONFIG
    sudo chmod 666 $KUBECONFIG
    # Update the server address
    sudo sed -i "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" $KUBECONFIG
fi

# Ensure the k3s yaml is readable by all
sudo chmod 666 /etc/rancher/k3s/k3s.yaml || true

# Test kubectl access before proceeding
if ! kubectl get nodes &>/dev/null; then
    log "ERROR: Cannot access Kubernetes cluster. Check permissions and configuration."
    log "Try running the main setup.sh script again with sudo."
    exit 1
fi

# Create namespaces (idempotent operation)
log "Creating namespaces..."
kubectl create namespace kubernetes-dashboard 2>/dev/null || log "Namespace kubernetes-dashboard already exists"
kubectl create namespace monitoring 2>/dev/null || log "Namespace monitoring already exists"
kubectl create namespace web 2>/dev/null || log "Namespace web already exists"

# Prepare hardware info for the Nginx dashboard
log "Preparing hardware information for the dashboard..."
mkdir -p charts/nginx/templates/hardware

# Extract CPU information
log "Extracting CPU information..."
cat /proc/cpuinfo > charts/nginx/templates/hardware/cpuinfo.txt

# Convert Android evidence to HTML
log "Converting Android evidence to HTML..."
if [ -f "android_evidence.txt" ]; then
    cat android_evidence.txt | sed 's/$/<br>/' | sed 's/^=/=/g' | sed 's/===/\<h3\>/g' | sed 's/==/\<h4\>/g' > charts/nginx/templates/hardware/android_evidence.html
    log "Android evidence converted to HTML format"
else
    echo "<p>Android evidence file not found. Please run detect_android.sh first.</p>" > charts/nginx/templates/hardware/android_evidence.html
    log "WARNING: android_evidence.txt not found"
fi

# Create ConfigMap for hardware info
log "Creating ConfigMap for hardware information..."
kubectl create configmap -n web hardware-info \
    --from-file=charts/nginx/templates/hardware/cpuinfo.txt \
    --from-file=charts/nginx/templates/hardware/android_evidence.html \
    --dry-run=client -o yaml | kubectl apply -f -

# Update the Nginx Deployment to mount hardware info
log "Updating Nginx Deployment to include hardware info..."
cat > /tmp/nginx-deployment-patch.yaml <<EOF
spec:
  template:
    spec:
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: hardware-info
        configMap:
          name: hardware-info
      containers:
      - name: nginx
        volumeMounts:
        - name: nginx-config
          mountPath: /usr/share/nginx/html/
        - name: hardware-info
          mountPath: /usr/share/nginx/html/hardware/
EOF

# Check if Dashboard is already deployed
log "Checking if Kubernetes Dashboard is already deployed..."
if kubectl get deployment -n kubernetes-dashboard kubernetes-dashboard-web &>/dev/null; then
    log "Kubernetes Dashboard is already deployed, skipping installation"
else
    # Deploy Dashboard
    log "Deploying Kubernetes Dashboard..."
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --set service.type=NodePort \
        --set service.nodePort=30443 \
        --set protocolHttp=true \
        --set service.externalPort=80 \
        --set metricsScraper.enabled=true || log "ERROR: Failed to deploy dashboard"

    # Create a direct NodePort service for the dashboard to ensure it's accessible
    kubectl apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: dashboard-nodeport
  namespace: kubernetes-dashboard
spec:
  type: NodePort
  ports:
  - port: 443
    targetPort: 8443
    nodePort: 30443
  selector:
    app.kubernetes.io/component: app
    app.kubernetes.io/instance: kubernetes-dashboard
    app.kubernetes.io/name: kong
YAML
fi

# Create service account and dashboard admin (idempotent operation)
log "Creating dashboard admin user..."
kubectl apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
YAML

kubectl apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
YAML

# Get token for dashboard access (regenerate each time for security)
log "Generating dashboard token..."
kubectl -n kubernetes-dashboard create token admin-user > $HOME/dashboard-token.txt || log "ERROR: Failed to create dashboard token"
chmod 666 $HOME/dashboard-token.txt

# Check if Glances is already deployed
log "Checking if Glances is already deployed..."
if kubectl get deployment -n monitoring glances &>/dev/null; then
    log "Glances is already deployed, updating if needed..."
    # Update Glances to ensure it has the latest configuration
    helm upgrade --install glances ./charts/glances -n monitoring || log "ERROR: Failed to upgrade Glances"
else
    # Deploy Glances
    log "Deploying Glances..."
    helm upgrade --install glances ./charts/glances -n monitoring || log "ERROR: Failed to deploy Glances"
fi

# Check if Nginx is already deployed
log "Checking if Nginx is already deployed..."
if kubectl get deployment -n web nginx &>/dev/null; then
    log "Nginx is already deployed, updating if needed..."
    # Update Nginx to ensure it has the latest configuration
    kubectl patch deployment nginx -n web --patch "$(cat /tmp/nginx-deployment-patch.yaml)" || log "ERROR: Failed to patch Nginx deployment"
    helm upgrade --install nginx ./charts/nginx -n web || log "ERROR: Failed to upgrade Nginx"
else
    # Deploy Nginx
    log "Deploying Nginx..."
    helm upgrade --install nginx ./charts/nginx -n web || log "ERROR: Failed to deploy Nginx"
    kubectl patch deployment nginx -n web --patch "$(cat /tmp/nginx-deployment-patch.yaml)" || log "ERROR: Failed to patch Nginx deployment"
fi

# Run tests
log "Running final tests..."
kubectl get nodes
kubectl get pods --all-namespaces || log "WARNING: Could not get pods"
kubectl get svc -n kubernetes-dashboard || log "WARNING: Could not get kubernetes-dashboard services"
kubectl get svc -n monitoring || log "WARNING: Could not get monitoring services"
kubectl get svc -n web || log "WARNING: Could not get web services"

log "Kubernetes operations completed!" 