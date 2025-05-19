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

# Create namespaces
kubectl create namespace kubernetes-dashboard || true
kubectl create namespace monitoring || true
kubectl create namespace web || true

# Deploy Dashboard
log "Deploying Kubernetes Dashboard..."
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --namespace kubernetes-dashboard \
    --set service.type=NodePort \
    --set service.nodePort=30443 \
    --set protocolHttp=true \
    --set service.externalPort=80 \
    --set metricsScraper.enabled=true

# Create service account and dashboard admin
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

# Get token for dashboard access
kubectl -n kubernetes-dashboard create token admin-user > $HOME/dashboard-token.txt
chmod 600 $HOME/dashboard-token.txt

# Deploy Glances
log "Deploying Glances..."
helm upgrade --install glances ./charts/glances -n monitoring

# Deploy Nginx
log "Deploying Nginx..."
helm upgrade --install nginx ./charts/nginx -n web

# Run tests
log "Running final tests..."
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get svc -n kubernetes-dashboard
kubectl get svc -n monitoring
kubectl get svc -n web

log "Kubernetes operations completed successfully!" 