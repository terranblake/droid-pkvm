#!/bin/bash

# Post-bootstrap setup script for Android pKVM
# This script should be executed on the Android pKVM instance after bootstrap
# It sets up SSH hardening, Kubernetes, and monitoring services

set -e
LOGFILE="$(pwd)/setup.log"
SSH_PUB_KEY="$1" # Path to SSH public key file
DASHBOARD_PORT="${2:-30443}" # Default port for K3s Dashboard
GLANCES_PORT="${3:-8080}" # Default port for Glances
NGINX_PORT="${4:-8081}" # Default port for Nginx
SSH_KEYFILE="$HOME/.ssh/droid_pkvm" # Path to store the new SSH key

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Validate required parameters and environment
validate_params() {
    # Check for SSH public key
    if [ -z "$SSH_PUB_KEY" ] || [ ! -f "$SSH_PUB_KEY" ]; then
        echo "ERROR: SSH public key file not provided or does not exist."
        echo "Usage: $0 <path_to_ssh_pubkey> [dashboard_port] [glances_port] [nginx_port]"
        echo "Example: $0 ~/.ssh/id_ed25519.pub 30443 8080 8081"
        exit 1
    fi

    log "Starting setup with the following parameters:"
    log "SSH public key: $SSH_PUB_KEY"
    log "Dashboard port: $DASHBOARD_PORT"
    log "Glances port: $GLANCES_PORT"
    log "Nginx port: $NGINX_PORT"
    
    # Check that we're in the droid-pkvm directory
    if [[ ! -f "$(pwd)/bootstrap.sh" ]]; then
        log "ERROR: This script must be run from the droid-pkvm directory"
        exit 1
    fi
}

# Generate SSH keypair and harden SSH 
harden_ssh() {
    log "Setting up SSH with provided public key..."
    
    # Set up authorized_keys with the provided key
    mkdir -p ~/.ssh
    
    # Ensure proper permissions before adding keys
    touch ~/.ssh/authorized_keys
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    
    # Add the provided key to authorized_keys
    log "Adding your provided public key to authorized_keys..."
    cat "$SSH_PUB_KEY" > /tmp/temp_pubkey
    cat /tmp/temp_pubkey >> ~/.ssh/authorized_keys
    rm /tmp/temp_pubkey
    
    # Make sure we have a local key for the VM too
    if [ ! -f "$SSH_KEYFILE" ]; then
        log "Generating local SSH keypair at $SSH_KEYFILE..."
        ssh-keygen -t ed25519 -f "$SSH_KEYFILE" -N "" -C "droid_pkvm_key"
        chmod 600 "$SSH_KEYFILE"
        log "Local SSH keypair generated"
    else
        log "Local SSH keypair already exists, using existing key"
    fi
    
    # Add the local key to authorized_keys too
    log "Adding local public key to authorized_keys..."
    cat "$SSH_KEYFILE.pub" >> ~/.ssh/authorized_keys
    
    # Ensure proper ownership and permissions
    sudo chown -R $(whoami):$(whoami) ~/.ssh
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/authorized_keys
    
    # Disable password authentication
    log "Hardening SSH configuration..."
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.hardened
    sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    sudo systemctl restart ssh
    
    log "SSH hardened, now using key-based authentication only"
    log "Public keys in authorized_keys:"
    cat ~/.ssh/authorized_keys
}

# Install Kubernetes (k3s)
install_k3s() {
    log "Installing k3s..."
    
    sudo curl -sfL https://get.k3s.io | sudo sh -
    sudo mkdir -p $HOME/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
    sudo sed -i "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    chmod 600 $HOME/.kube/config
    export KUBECONFIG=$HOME/.kube/config
    echo "export KUBECONFIG=$HOME/.kube/config" >> $HOME/.bashrc

    # Wait for node to be ready
    log "Waiting for node to be ready..."
    sudo timeout 120s bash -c 'until kubectl get nodes | grep " Ready "; do sleep 5; done'
    
    log "k3s installed"
}

# Install Helm
install_helm() {
    log "Installing Helm..."
    
    # Check if Helm is already available (it should be part of k3s)
    if command -v helm &> /dev/null; then
        log "Helm is already installed with k3s"
        helm version
    else
        log "Helm not found, installing manually..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # Add Kubernetes Dashboard repo
    helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
    helm repo update
    
    log "Helm installed"
}

# Configure firewall for services
configure_firewall() {
    log "Configuring firewall for services..."
    
    sudo ufw allow $DASHBOARD_PORT/tcp comment "K3s Dashboard"
    sudo ufw allow $GLANCES_PORT/tcp comment "Glances"
    sudo ufw allow $NGINX_PORT/tcp comment "Nginx"
    sudo ufw allow 6443/tcp comment "Kubernetes API"
    
    log "Firewall configured for services"
}

# Deploy Kubernetes Dashboard
deploy_dashboard() {
    log "Deploying Kubernetes Dashboard..."
    
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

    # Wait for deployment to be ready
    kubectl -n kubernetes-dashboard wait --for=condition=available deployment/kubernetes-dashboard --timeout=60s

    # Get token for dashboard access
    kubectl -n kubernetes-dashboard create token admin-user > ~/dashboard-token.txt
    chmod 600 ~/dashboard-token.txt

    HOST_IP=$(hostname -I | awk '{print $1}')
    log "Kubernetes Dashboard available at: http://$HOST_IP:$DASHBOARD_PORT"
    log "Access token saved to: ~/dashboard-token.txt"
    
    log "Kubernetes Dashboard deployed"
}

# Collect hardware info and run Android detection
collect_hardware_info() {
    log "Collecting hardware and Android environment information..."
    
    # Create directory for hardware info
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

    # Run the Android detection script
    log "Running Android detection script..."
    chmod +x ./detect_android.sh
    ./detect_android.sh
    cp android_evidence.txt ~/hardware-info/

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
            echo "Product Name: $(cat ~/hardware-info/product_name.txt 2>/dev/null)"
            echo "System Vendor: $(cat ~/hardware-info/sys_vendor.txt 2>/dev/null)"
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
        
        # Add summary from detect_android.sh
        echo -e "\n=== Detection Script Summary ==="
        grep "CONCLUSION" android_evidence.txt
        
        echo "</pre>"
    } > ~/hardware-info/android_evidence.html

    # Copy collected data to Nginx chart directory
    mkdir -p ./charts/nginx/templates/hardware
    cp ~/hardware-info/* ./charts/nginx/templates/hardware/
    
    log "Hardware information collected and saved"
}

# Deploy Glances monitoring
deploy_glances() {
    log "Deploying Glances..."

    # Update port in values file
    sed -i "s/nodePort: [0-9]*/nodePort: $GLANCES_PORT/" ./charts/glances/values.yaml

    # Install the Helm chart
    kubectl create namespace monitoring || true
    helm upgrade --install glances ./charts/glances -n monitoring

    # Wait for deployment to be ready
    kubectl -n monitoring wait --for=condition=available deployment/glances --timeout=60s

    HOST_IP=$(hostname -I | awk '{print $1}')
    log "Glances available at: http://$HOST_IP:$GLANCES_PORT"
    
    log "Glances deployed"
}

# Deploy Nginx with hardware info
deploy_nginx() {
    log "Deploying Nginx with hardware info..."

    # Update port in values file
    sed -i "s/nodePort: [0-9]*/nodePort: $NGINX_PORT/" ./charts/nginx/values.yaml

    # Install the Helm chart
    kubectl create namespace web || true
    helm upgrade --install nginx ./charts/nginx -n web

    # Wait for deployment to be ready
    kubectl -n web wait --for=condition=available deployment/nginx --timeout=60s

    HOST_IP=$(hostname -I | awk '{print $1}')
    log "Nginx dashboard available at: http://$HOST_IP:$NGINX_PORT"
    
    log "Nginx deployed with hardware info"
}

# Run tests to verify all components
run_tests() {
    log "Running tests to verify all components..."
    
    # Test Kubernetes/k3s
    log "Testing k3s..."
    kubectl get nodes
    kubectl get pods --all-namespaces

    # Test Dashboard
    log "Testing Dashboard..."
    kubectl get svc -n kubernetes-dashboard

    # Test Glances
    log "Testing Glances..."
    kubectl get svc -n monitoring

    # Test Nginx
    log "Testing Nginx..."
    kubectl get svc -n web

    # Summarize ports
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "=== Service URLs ==="
    echo "Kubernetes Dashboard: http://$HOST_IP:$DASHBOARD_PORT"
    echo "Glances: http://$HOST_IP:$GLANCES_PORT"
    echo "Nginx: http://$HOST_IP:$NGINX_PORT"
    
    log "Tests completed"
}

# Main function
main() {
    validate_params
    harden_ssh
    install_k3s
    install_helm
    configure_firewall
    collect_hardware_info
    deploy_dashboard
    deploy_glances
    deploy_nginx
    run_tests
    
    log "Setup completed successfully!"
    echo "======================================================================"
    echo "Android pKVM setup completed!"
    echo ""
    echo "You have configured the following SSH keys for access:"
    echo "1. Your provided key: $SSH_PUB_KEY"
    echo "2. The locally generated key at: $SSH_KEYFILE"
    echo ""
    echo "Make sure to save your private key to access this VM!"
    echo ""
    echo "Services:"
    HOST_IP=$(hostname -I | awk '{print $1}')
    echo "  Kubernetes Dashboard: http://$HOST_IP:$DASHBOARD_PORT"
    echo "  Glances: http://$HOST_IP:$GLANCES_PORT"
    echo "  Nginx (Hardware Info): http://$HOST_IP:$NGINX_PORT"
    echo ""
    echo "Dashboard token is stored at: ~/dashboard-token.txt"
    echo "======================================================================"
}

# Run the main function
main 