#!/bin/bash

# Post-bootstrap setup script for Android pKVM
# This script is intended to run on your local machine, not on the Android pKVM instance
# It will SSH into the pKVM instance using the default credentials, harden SSH,
# and install Kubernetes, Helm, Dashboard, Glances, and an Nginx landing page.

set -e
LOGFILE="$(pwd)/setup.log"
TARGET_HOST="$1" # IP address of the pKVM instance
SSH_PORT="${2:-2222}" # Default SSH port
SSH_KEYFILE="$HOME/.ssh/droid_pkvm" # Path to store the new SSH key
DEFAULT_USER="droid"
DEFAULT_PASS="droid"
DASHBOARD_PORT="${3:-30443}" # Default port for K3s Dashboard
GLANCES_PORT="${4:-8080}" # Default port for Glances
NGINX_PORT="${5:-8081}" # Default port for Nginx

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Validate required parameters
validate_params() {
    if [ -z "$TARGET_HOST" ]; then
        echo "ERROR: Missing target host IP address."
        echo "Usage: $0 <target_host_ip> [ssh_port] [dashboard_port] [glances_port] [nginx_port]"
        exit 1
    fi
    
    log "Target host: $TARGET_HOST"
    log "SSH port: $SSH_PORT"
    log "Dashboard port: $DASHBOARD_PORT"
    log "Glances port: $GLANCES_PORT"
    log "Nginx port: $NGINX_PORT"
}

# Generate SSH keypair and harden SSH on the pKVM instance
harden_ssh() {
    log "Generating SSH keypair at $SSH_KEYFILE..."
    
    # Generate SSH keypair if it doesn't exist
    if [ ! -f "$SSH_KEYFILE" ]; then
        ssh-keygen -t ed25519 -f "$SSH_KEYFILE" -N "" -C "droid_pkvm_key"
        chmod 600 "$SSH_KEYFILE"
        log "SSH keypair generated"
    else
        log "SSH keypair already exists, using existing key"
    fi
    
    # Copy SSH public key to pKVM instance
    log "Copying SSH public key to pKVM instance..."
    sshpass -p "$DEFAULT_PASS" ssh-copy-id -i "$SSH_KEYFILE" -p "$SSH_PORT" -o StrictHostKeyChecking=no "$DEFAULT_USER@$TARGET_HOST"
    
    # Disable password authentication
    log "Hardening SSH configuration..."
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << 'EOF'
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.hardened
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo systemctl restart ssh
EOF
    
    log "SSH hardened, now using key-based authentication only"
}

# Install Kubernetes (k3s)
install_k3s() {
    log "Installing k3s on pKVM instance..."
    
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << 'EOF'
sudo curl -sfL https://get.k3s.io | sudo sh -
sudo mkdir -p $HOME/.kube
sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo sed -i "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
chmod 600 $HOME/.kube/config
export KUBECONFIG=$HOME/.kube/config
echo "export KUBECONFIG=$HOME/.kube/config" >> $HOME/.bashrc

# Wait for node to be ready
echo "Waiting for node to be ready..."
sudo timeout 120s bash -c 'until kubectl get nodes | grep " Ready "; do sleep 5; done'
EOF
    
    log "k3s installed on pKVM instance"
}

# Install Helm
install_helm() {
    log "Installing Helm on pKVM instance..."
    
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << 'EOF'
# Check if Helm is already available (it should be part of k3s)
if command -v helm &> /dev/null; then
    echo "Helm is already installed with k3s"
    helm version
else
    echo "Helm not found, installing manually..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Add Kubernetes Dashboard repo
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update
EOF
    
    log "Helm installed on pKVM instance"
}

# Configure firewall for services
configure_firewall() {
    log "Configuring firewall for services on pKVM instance..."
    
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << EOF
sudo ufw allow $DASHBOARD_PORT/tcp comment "K3s Dashboard"
sudo ufw allow $GLANCES_PORT/tcp comment "Glances"
sudo ufw allow $NGINX_PORT/tcp comment "Nginx"
sudo ufw allow 6443/tcp comment "Kubernetes API"
EOF
    
    log "Firewall configured for services"
}

# Deploy Kubernetes Dashboard
deploy_dashboard() {
    log "Deploying Kubernetes Dashboard on pKVM instance..."
    
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << EOF
# Create namespace
kubectl create namespace kubernetes-dashboard || true

# Deploy dashboard
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
    --namespace kubernetes-dashboard \
    --set service.type=NodePort \
    --set service.nodePort=$DASHBOARD_PORT \
    --set protocolHttp=true \
    --set service.externalPort=80 \
    --set metricsScraper.enabled=true

# Create service account and dashboard admin
cat <<YAML | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
YAML

cat <<YAML | kubectl apply -f -
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

# Wait for deployment to be ready
kubectl -n kubernetes-dashboard wait --for=condition=available deployment/kubernetes-dashboard --timeout=60s

# Get token for dashboard access
kubectl -n kubernetes-dashboard create token admin-user > ~/dashboard-token.txt
chmod 600 ~/dashboard-token.txt

HOST_IP=\$(hostname -I | awk '{print \$1}')
echo "Kubernetes Dashboard available at: http://\$HOST_IP:$DASHBOARD_PORT"
echo "Access token saved to: ~/dashboard-token.txt"
EOF
    
    log "Kubernetes Dashboard deployed"
}

# Deploy Glances monitoring
deploy_glances() {
    log "Deploying Glances on pKVM instance..."
    
    # First, copy the Helm chart files from the repository to the pKVM instance
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << EOF
# Update the port value in values.yaml
cd ~/droid-pkvm/charts/glances
sed -i "s/nodePort: [0-9]*/nodePort: $GLANCES_PORT/" values.yaml

# Install the Helm chart
kubectl create namespace monitoring || true
helm upgrade --install glances ~/droid-pkvm/charts/glances -n monitoring

# Wait for deployment to be ready
kubectl -n monitoring wait --for=condition=available deployment/glances --timeout=60s

HOST_IP=\$(hostname -I | awk '{print \$1}')
echo "Glances available at: http://\$HOST_IP:$GLANCES_PORT"
EOF
    
    log "Glances deployed"
}

# Deploy Nginx with hardware info
deploy_nginx() {
    log "Deploying Nginx with hardware info on pKVM instance..."
    
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << EOF
# First, gather hardware information
mkdir -p ~/hardware-info

# CPU Info
cat /proc/cpuinfo > ~/hardware-info/cpuinfo.txt

# Memory Info
cat /proc/meminfo > ~/hardware-info/meminfo.txt

# Kernel Info
uname -a > ~/hardware-info/kernel.txt

# Check for Android-specific identifiers
cat /proc/version > ~/hardware-info/version.txt

# Check for Virtualization information
if command -v lscpu &> /dev/null; then
    lscpu | grep -i "virtualization\|hyper" > ~/hardware-info/virt.txt
fi

# Check DMI information
if [ -d "/sys/class/dmi/id/" ]; then
    ls -la /sys/class/dmi/id/ > ~/hardware-info/dmi-files.txt
    cat /sys/class/dmi/id/product_name 2>/dev/null > ~/hardware-info/product_name.txt
    cat /sys/class/dmi/id/sys_vendor 2>/dev/null > ~/hardware-info/sys_vendor.txt
fi

# Check for any Android properties if accessible
if command -v getprop &> /dev/null; then
    getprop > ~/hardware-info/android_props.txt
fi

# Create a summary file that highlights definitive Android evidence
{
    echo "<h2>Evidence of Android Environment</h2><pre>"
    
    # Check for Android specific content in various files
    echo "=== Checking kernel version for Android markers ==="
    grep -i "android" ~/hardware-info/kernel.txt 2>/dev/null || echo "No Android markers in kernel"
    
    echo -e "\n=== Checking system version for Android markers ==="
    grep -i "android" ~/hardware-info/version.txt 2>/dev/null || echo "No Android markers in version"
    
    if [ -f ~/hardware-info/product_name.txt ]; then
        echo -e "\n=== Product Information ==="
        echo "Product Name: \$(cat ~/hardware-info/product_name.txt 2>/dev/null)"
        echo "System Vendor: \$(cat ~/hardware-info/sys_vendor.txt 2>/dev/null)"
    fi
    
    if [ -f ~/hardware-info/android_props.txt ]; then
        echo -e "\n=== Android Properties (definitive proof) ==="
        cat ~/hardware-info/android_props.txt
    else
        echo -e "\n=== No Android properties file found ==="
    fi
    
    # Try additional Android checks
    echo -e "\n=== Checking for /system/build.prop (Android system file) ==="
    if [ -f /system/build.prop ]; then
        cat /system/build.prop | grep -i "ro.product" || echo "No product info in build.prop"
    else
        echo "/system/build.prop not found"
    fi
    
    echo -e "\n=== Checking for pKVM evidence ==="
    dmesg | grep -i "pkvm\|protected\|hypervisor" || echo "No pKVM specific markers found in dmesg"
    
    echo "</pre>"
} > ~/hardware-info/android_evidence.html

# Update the port value in values.yaml for Nginx
cd ~/droid-pkvm/charts/nginx
sed -i "s/nodePort: [0-9]*/nodePort: $NGINX_PORT/" values.yaml

# Copy the hardware information to the configmap
mkdir -p ~/droid-pkvm/charts/nginx/templates/hardware
cp ~/hardware-info/* ~/droid-pkvm/charts/nginx/templates/hardware/

# Install the Helm chart
kubectl create namespace web || true
helm upgrade --install nginx ~/droid-pkvm/charts/nginx -n web

# Wait for deployment to be ready
kubectl -n web wait --for=condition=available deployment/nginx --timeout=60s

HOST_IP=\$(hostname -I | awk '{print \$1}')
echo "Nginx dashboard available at: http://\$HOST_IP:$NGINX_PORT"
EOF
    
    log "Nginx deployed with hardware info"
}

# Run tests to verify all components
run_tests() {
    log "Running tests to verify all components..."
    
    ssh -i "$SSH_KEYFILE" -p "$SSH_PORT" "$DEFAULT_USER@$TARGET_HOST" << EOF
# Test Kubernetes/k3s
echo "Testing k3s..."
kubectl get nodes
kubectl get pods --all-namespaces

# Test Dashboard
echo "Testing Dashboard..."
kubectl get svc -n kubernetes-dashboard

# Test Glances
echo "Testing Glances..."
kubectl get svc -n monitoring

# Test Nginx
echo "Testing Nginx..."
kubectl get svc -n web

# Summarize ports
HOST_IP=\$(hostname -I | awk '{print \$1}')
echo ""
echo "=== Service URLs ==="
echo "Kubernetes Dashboard: http://\$HOST_IP:$DASHBOARD_PORT"
echo "Glances: http://\$HOST_IP:$GLANCES_PORT"
echo "Nginx: http://\$HOST_IP:$NGINX_PORT"
EOF
    
    log "Tests completed"
}

# Main function
main() {
    validate_params
    harden_ssh
    install_k3s
    install_helm
    configure_firewall
    deploy_dashboard
    deploy_glances
    deploy_nginx
    run_tests
    
    log "Setup completed successfully!"
    echo "======================================================================"
    echo "Android pKVM setup completed!"
    echo ""
    echo "The SSH key for accessing the pKVM instance is at: $SSH_KEYFILE"
    echo "To access the pKVM instance, use:"
    echo "  ssh -i $SSH_KEYFILE -p $SSH_PORT $DEFAULT_USER@$TARGET_HOST"
    echo ""
    echo "Services:"
    echo "  Kubernetes Dashboard: http://$TARGET_HOST:$DASHBOARD_PORT"
    echo "  Glances: http://$TARGET_HOST:$GLANCES_PORT"
    echo "  Nginx (Hardware Info): http://$TARGET_HOST:$NGINX_PORT"
    echo ""
    echo "Dashboard token is stored on the pKVM instance at: ~/dashboard-token.txt"
    echo "======================================================================"
}

# Run the main function
main 