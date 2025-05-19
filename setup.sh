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
    
    # Set up SSH directory and authorized_keys with the provided key
    mkdir -p "$DROID_HOME/.ssh"
    touch "$DROID_HOME/.ssh/authorized_keys"
    
    # Add the provided key to authorized_keys
    log "Adding your provided public key to authorized_keys..."
    cat "$SSH_PUB_KEY" >> "$DROID_HOME/.ssh/authorized_keys"
    
    # Make sure we have a local key for the VM too
    if [ ! -f "$SSH_KEYFILE" ]; then
        log "Generating local SSH keypair at $SSH_KEYFILE..."
        ssh-keygen -t ed25519 -f "$SSH_KEYFILE" -N "" -C "droid_pkvm_key"
        log "Local SSH keypair generated"
    else
        log "Local SSH keypair already exists, using existing key"
    fi
    
    # Add the local key to authorized_keys too
    log "Adding local public key to authorized_keys..."
    cat "$SSH_KEYFILE.pub" >> "$DROID_HOME/.ssh/authorized_keys"
    
    # Set proper permissions
    chmod 700 "$DROID_HOME/.ssh"
    chmod 600 "$DROID_HOME/.ssh/authorized_keys"
    chmod 600 "$SSH_KEYFILE"
    
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
    
    # Restart SSH service to apply changes
    systemctl restart ssh
    
    log "SSH configured with key-based authentication and password authentication both enabled"
    log "Public keys in authorized_keys:"
    cat "$DROID_HOME/.ssh/authorized_keys"
}

# Install Kubernetes (k3s)
install_k3s() {
    log "Installing k3s..."
    
    curl -sfL https://get.k3s.io | sh -
    mkdir -p $DROID_HOME/.kube
    cp /etc/rancher/k3s/k3s.yaml $DROID_HOME/.kube/config
    sed -i "s/127.0.0.1/$(hostname -I | awk '{print $1}')/g" $DROID_HOME/.kube/config
    chmod 755 $DROID_HOME/.kube
    chmod 644 $DROID_HOME/.kube/config
    
    # Add KUBECONFIG to user's .bashrc
    echo "export KUBECONFIG=$DROID_HOME/.kube/config" >> $DROID_HOME/.bashrc

    # Wait for node to be ready
    log "Waiting for node to be ready..."
    timeout 120s bash -c 'until kubectl get nodes | grep " Ready "; do sleep 5; done'
    
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
    # Run as droid user to ensure proper permissions
    su - $DROID_USER -c "helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/"
    su - $DROID_USER -c "helm repo update"
    
    log "Helm installed"
}

# Configure firewall for services
configure_firewall() {
    log "Configuring firewall for services..."
    
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
    chmod 755 detect_android.sh
    chmod 755 kubernetes-setup.sh
    
    # Run Android detection and Kubernetes setup as droid user
    log "Running Kubernetes operations as droid user..."
    su - $DROID_USER -c "cd $DROID_HOME/droid-pkvm && ./detect_android.sh && ./kubernetes-setup.sh"
    
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