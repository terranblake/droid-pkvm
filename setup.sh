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
    log "Setting appropriate permissions on droid home directory..."
    chmod -R 755 $DROID_HOME
    chmod -R 755 $DROID_HOME/droid-pkvm
    
    # Ensure SSH directory permissions are preserved
    if [ -d "$DROID_HOME/.ssh" ]; then
        log "Preserving secure SSH directory permissions..."
        chmod 700 "$DROID_HOME/.ssh"
        [ -f "$DROID_HOME/.ssh/authorized_keys" ] && chmod 600 "$DROID_HOME/.ssh/authorized_keys"
        find "$DROID_HOME/.ssh" -name "id_*" ! -name "*.pub" -exec chmod 600 {} \;
        find "$DROID_HOME/.ssh" -name "*.pub" -exec chmod 644 {} \;
    fi
    
    log "Permissions set appropriately on $DROID_HOME"
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
    
    # Expand tilde in path if present
    if [[ "$SSH_PUB_KEY" == "~/"* ]]; then
        SSH_PUB_KEY="$HOME/${SSH_PUB_KEY:2}"
        log "Expanded SSH key path to: $SSH_PUB_KEY"
    fi
    
    if [ ! -f "$SSH_PUB_KEY" ]; then
        log "ERROR: SSH public key file '$SSH_PUB_KEY' does not exist."
        echo "Usage: $0 <path_to_ssh_pubkey> [dashboard_port] [glances_port] [nginx_port]"
        echo "Example: $0 ~/.ssh/id_ed25519.pub 30443 8080 30081"
        exit 1
    fi
    
    # Check file size - should be small for a public key
    KEY_SIZE=$(stat -c%s "$SSH_PUB_KEY" 2>/dev/null || stat -f%z "$SSH_PUB_KEY" 2>/dev/null)
    if [ -n "$KEY_SIZE" ] && [ "$KEY_SIZE" -gt 10000 ]; then
        log "WARNING: The key file is unusually large ($KEY_SIZE bytes) for a public key."
        echo "Please verify you are providing a public key (not a private key or other file)."
        read -p "Continue anyway? (y/n): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            log "Setup aborted by user"
            exit 1
        fi
    fi
    
    # Validate the key format
    if ssh-keygen -l -f "$SSH_PUB_KEY" &>/dev/null; then
        KEY_INFO=$(ssh-keygen -l -f "$SSH_PUB_KEY")
        log "SSH public key: $SSH_PUB_KEY (VALID) - $KEY_INFO"
        SSH_KEY_VALID=true
    else
        log "ERROR: The provided file '$SSH_PUB_KEY' is not a valid SSH public key."
        echo "Please provide a valid SSH public key file."
        exit 1
    fi
    
    # Validate port numbers
    if ! [[ "$DASHBOARD_PORT" =~ ^[0-9]+$ ]] || [ "$DASHBOARD_PORT" -lt 1 ] || [ "$DASHBOARD_PORT" -gt 65535 ]; then
        log "ERROR: Invalid dashboard port number: $DASHBOARD_PORT"
        exit 1
    fi
    
    if ! [[ "$GLANCES_PORT" =~ ^[0-9]+$ ]] || [ "$GLANCES_PORT" -lt 1 ] || [ "$GLANCES_PORT" -gt 65535 ]; then
        log "ERROR: Invalid glances port number: $GLANCES_PORT"
        exit 1
    fi
    
    # NodePort validation - must be in range 30000-32767
    if ! [[ "$NGINX_PORT" =~ ^[0-9]+$ ]] || [ "$NGINX_PORT" -lt 30000 ] || [ "$NGINX_PORT" -gt 32767 ]; then
        log "ERROR: Invalid nginx port number: $NGINX_PORT (must be in range 30000-32767 for NodePort)"
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
    
    # Validate key format and content before using it
    log "Validating the SSH public key format and content..."
    if ! ssh-keygen -l -f "$SSH_PUB_KEY" &>/dev/null; then
        log "ERROR: The provided file '$SSH_PUB_KEY' is not a valid SSH public key."
        echo "Please provide a valid SSH public key file."
        exit 1
    fi
    
    # Verify the key content contains ssh-rsa, ssh-ed25519, or ssh-dss
    KEY_CONTENT=$(cat "$SSH_PUB_KEY")
    if ! echo "$KEY_CONTENT" | grep -qE "^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sha2)"; then
        log "ERROR: The SSH key does not appear to be a valid public key format."
        echo "The key should start with ssh-rsa, ssh-ed25519, ecdsa-sha2, or ssh-dss."
        exit 1
    fi
    
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
    
    # Verify keys were properly added
    log "Verifying keys were added to authorized_keys..."
    if ! grep -q "$(cat "$SSH_PUB_KEY")" "$DROID_HOME/.ssh/authorized_keys"; then
        log "ERROR: Failed to add provided key to authorized_keys. Adding again..."
        cat "$SSH_PUB_KEY" >> "$DROID_HOME/.ssh/authorized_keys"
    fi
    
    # Set proper SSH permissions
    log "Setting proper SSH directory and file permissions..."
    chmod 700 "$DROID_HOME/.ssh"
    chmod 600 "$DROID_HOME/.ssh/authorized_keys"
    chmod 600 "$DROID_HOME/.ssh/droid_pkvm"
    chmod 644 "$DROID_HOME/.ssh/droid_pkvm.pub"
    
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
    
    # Test SSH configuration
    log "Testing SSH configuration file syntax..."
    if ! sshd -t; then
        log "ERROR: SSH configuration has syntax errors"
        # Try to fix by resetting to known good config
        cp /etc/ssh/sshd_config.bak.hardened /etc/ssh/sshd_config
        echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config
        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
        echo "StrictModes no" >> /etc/ssh/sshd_config
    fi
    
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
    log "Setting executable permissions on scripts..."
    find $DROID_HOME/droid-pkvm -name "*.sh" -exec chmod +x {} \;
    
    # Ensure SSH permissions stay secure
    log "Ensuring SSH permissions remain secure..."
    chmod 700 "$DROID_HOME/.ssh"
    chmod 600 "$DROID_HOME/.ssh/authorized_keys"
    chmod 600 "$DROID_HOME/.ssh/droid_pkvm"
    chmod 644 "$DROID_HOME/.ssh/droid_pkvm.pub"
    
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