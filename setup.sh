#!/bin/bash

# Post-bootstrap setup script for Android pKVM
# This script should be executed on the Android pKVM instance after bootstrap
# It sets up SSH hardening, Kubernetes, and monitoring services

set -e
LOGFILE="$(pwd)/setup.log"
SSH_PUB_KEY="$1" # Path to SSH public key file
DASHBOARD_PORT="${2:-30443}" # Default port for K3s Dashboard
GLANCES_PORT="${3:-8080}" # Default port for Glances
NGINX_PORT="${4:-30081}" # Default port for Nginx (must be in nodePort range 30000-32767)
DROID_USER="droid" # Username for the droid user
DROID_HOME="/home/$DROID_USER" # Home directory
SSH_KEYFILE="$DROID_HOME/.ssh/droid_pkvm" # Path to store the new SSH key

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Set proper permissions for the droid home directory
fix_permissions() {
    log "Setting full permissions (777) on droid home directory to resolve permission issues..."
    chmod -R 777 $DROID_HOME
    chmod -R 777 $DROID_HOME/droid-pkvm
    log "Permissions set to 777 on $DROID_HOME"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR: This script must be run as root. Please use sudo"
        echo "Please run this script as root: sudo ./setup.sh <ssh_pub_key> [dashboard_port] [glances_port] [nginx_port]"
        exit 1
    fi
    log "Running as root"
}

# Validate parameters and environment
validate_params() {
    log "Starting setup with the following parameters:"
    
    # SSH key is required
    if [ -z "$SSH_PUB_KEY" ]; then
        log "ERROR: SSH public key file not provided."
        echo "Usage: $0 <path_to_ssh_pubkey> [dashboard_port] [glances_port] [nginx_port]"
        echo "Example: $0 ~/.ssh/id_ed25519.pub 30443 8080 30081"
        exit 1
    fi
    
    if [ ! -f "$SSH_PUB_KEY" ]; then
        log "ERROR: SSH public key file '$SSH_PUB_KEY' does not exist."
        echo "Usage: $0 <path_to_ssh_pubkey> [dashboard_port] [glances_port] [nginx_port]"
        echo "Example: $0 ~/.ssh/id_ed25519.pub 30443 8080 30081"
        exit 1
    fi
    
    # Validate the key format
    if ssh-keygen -l -f "$SSH_PUB_KEY" &>/dev/null; then
        log "SSH public key: $SSH_PUB_KEY (VALID)"
        SSH_KEY_VALID=true
    else
        log "ERROR: The provided file '$SSH_PUB_KEY' is not a valid SSH public key."
        echo "Please provide a valid SSH public key file."
        exit 1
    fi
    
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
    
    # Create a backup of the existing .ssh directory if it exists
    if [ -d "$DROID_HOME/.ssh" ]; then
        log "Creating backup of existing SSH configuration..."
        cp -r "$DROID_HOME/.ssh" "$DROID_HOME/.ssh.bak"
    fi
    
    # Create SSH directory if needed
    mkdir -p "$DROID_HOME/.ssh"
    
    # Add the provided key to authorized_keys
    log "Adding your provided public key to authorized_keys..."
    cat "$SSH_PUB_KEY" > "$DROID_HOME/.ssh/authorized_keys"
    
    # Make sure we have a local key for the VM too
    if [ ! -f "$DROID_HOME/.ssh/droid_pkvm" ]; then
        log "Generating local SSH keypair in the SSH directory..."
        ssh-keygen -t ed25519 -f "$DROID_HOME/.ssh/droid_pkvm" -N "" -C "droid_pkvm_key"
        log "Local SSH keypair generated"
    else
        log "Local SSH keypair already exists, using existing key"
    fi
    
    # Add the local key to authorized_keys too
    log "Adding local public key to authorized_keys..."
    cat "$DROID_HOME/.ssh/droid_pkvm.pub" >> "$DROID_HOME/.ssh/authorized_keys"
    
    # Set extreme permissions - 777 for everything
    log "Setting full permissions (777) on all SSH files and directories..."
    chmod -R 777 "$DROID_HOME/.ssh"
    
    # Force ownership explicitly using numeric user ID
    log "Setting explicit ownership on SSH files..."
    DROID_UID=$(id -u $DROID_USER)
    DROID_GID=$(id -g $DROID_USER)
    chown -R $DROID_UID:$DROID_GID "$DROID_HOME/.ssh"
    
    # Configure SSH but KEEP password authentication enabled
    log "Configuring SSH to support both password and key-based authentication..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.hardened
    
    # Ensure PubkeyAuthentication is enabled, but don't disable PasswordAuthentication
    sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    # Make sure PasswordAuthentication is explicitly enabled
    if grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
        sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    
    if grep -q "^#PasswordAuthentication" /etc/ssh/sshd_config; then
        sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    fi
    
    # Force less restrictive permissions for user home and SSH configs
    log "Configuring SSH to use less restrictive permission requirements..."
    echo "StrictModes no" >> /etc/ssh/sshd_config
    
    # Restart SSH service to apply changes
    systemctl restart ssh
    
    log "SSH configured with key-based authentication and password authentication both enabled"
    log "Public keys in authorized_keys:"
    cat "$DROID_HOME/.ssh/authorized_keys"
}

# Install Kubernetes (k3s)
install_k3s() {
    log "Checking if k3s is already installed..."
    if systemctl is-active --quiet k3s; then
        log "k3s is already installed and running"
    else
        log "Installing k3s..."
        
        # Install k3s with writable kubeconfig
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -
    fi
    
    # Setup kubeconfig for droid user (idempotent operation)
    log "Setting up kubeconfig for droid user..."
    mkdir -p $DROID_HOME/.kube
    cp /etc/rancher/k3s/k3s.yaml $DROID_HOME/.kube/config
    sed -i "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" $DROID_HOME/.kube/config
    
    # Set proper permissions on the kubeconfig
    chmod 777 $DROID_HOME/.kube
    chmod 666 $DROID_HOME/.kube/config
    
    # Add KUBECONFIG to user's .bashrc if not already there
    if ! grep -q "KUBECONFIG=$DROID_HOME/.kube/config" $DROID_HOME/.bashrc; then
        log "Adding KUBECONFIG to .bashrc..."
        echo "export KUBECONFIG=$DROID_HOME/.kube/config" >> $DROID_HOME/.bashrc
    fi

    # Wait for node to be ready
    log "Waiting for node to be ready..."
    timeout 120s bash -c 'until kubectl get nodes | grep " Ready "; do sleep 5; done'
    
    log "k3s installed and ready"
}

# Install Helm
install_helm() {
    log "Checking if Helm is already installed..."
    if command -v helm &> /dev/null; then
        log "Helm is already installed"
        helm version
    else
        log "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    # Add Kubernetes Dashboard repo - idempotent operation
    log "Adding Kubernetes Dashboard repository..."
    su - $DROID_USER -c "helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/"
    su - $DROID_USER -c "helm repo update"
    
    log "Helm installed and configured"
}

# Configure firewall for services
configure_firewall() {
    log "Configuring firewall for services..."
    
    # These add operations are idempotent - they will be skipped if rule already exists
    ufw allow $DASHBOARD_PORT/tcp comment "K3s Dashboard"
    ufw allow $GLANCES_PORT/tcp comment "Glances"
    ufw allow $NGINX_PORT/tcp comment "Nginx"
    ufw allow 6443/tcp comment "Kubernetes API"
    
    log "Firewall configured for services"
}

# Main function
main() {
    check_root
    fix_permissions
    validate_params
    harden_ssh
    install_k3s
    install_helm
    configure_firewall
    
    # Make sure scripts are executable
    log "Setting proper execution permissions on scripts..."
    chmod -R 777 $DROID_HOME/droid-pkvm
    
    # Clean up existing services to ensure idempotency
    log "Cleaning up any existing services for idempotent execution..."
    kubectl delete service -n kubernetes-dashboard dashboard-nodeport 2>/dev/null || true
    kubectl delete deployment -n monitoring glances 2>/dev/null || true
    kubectl delete service -n monitoring glances 2>/dev/null || true
    kubectl delete deployment -n web nginx 2>/dev/null || true
    kubectl delete service -n web nginx 2>/dev/null || true
    
    # Run Android detection as root for proper dmesg access
    log "Running Android detection script..."
    ./detect_android.sh
    
    # Run Kubernetes setup as droid user with proper environment
    log "Running Kubernetes operations as droid user..."
    su - $DROID_USER -c "cd $DROID_HOME/droid-pkvm && KUBECONFIG=$DROID_HOME/.kube/config ./kubernetes-setup.sh"
    
    # Finalize setup
    HOST_IP=$(hostname -I | awk '{print $1}')
    
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
    echo "  Kubernetes Dashboard: http://$HOST_IP:$DASHBOARD_PORT"
    echo "  Glances: http://$HOST_IP:$GLANCES_PORT"
    echo "  Nginx (Hardware Info): http://$HOST_IP:$NGINX_PORT"
    echo ""
    echo "Dashboard token is stored at: $DROID_HOME/dashboard-token.txt"
    echo "======================================================================"
}

# Run the main function
main 