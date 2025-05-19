#!/bin/bash

# Debian WireGuard & SSH Setup Script for Android pKVM
# This script sets up the core requirements for an Android pKVM instance
# including WireGuard VPN (optional), SSH for user 'droid', and initial system configuration.

set -e
LOGFILE="$HOME/bootstrap.log"
WG_SERVER_IP="$1" # WireGuard server IP (optional)
WG_SERVER_PORT="51820" # Default WireGuard port, adjust if needed
WG_CLIENT_IP="10.0.0.7/24" # Client IP on WireGuard network
WG_SERVER_PUBKEY="$2" # WireGuard server's public key (optional)
WG_CLIENT_PUBLICKEY="$3" # WireGuard client's public key (optional)
WG_CLIENT_PRIVATEKEY="$4" # WireGuard client's private key (optional)
WG_INTERFACE="wg0"
WG_ENABLED=true

# If any WireGuard parameter is missing, disable WireGuard setup
if [ -z "$WG_SERVER_IP" ] || [ -z "$WG_SERVER_PUBKEY" ] || [ -z "$WG_CLIENT_PUBLICKEY" ] || [ -z "$WG_CLIENT_PRIVATEKEY" ]; then
    WG_ENABLED=false
fi

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Check for root privileges
check_root() {
    log "Checking for root privileges..."
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root."
        exit 1
    fi
    log "Running with root privileges"
}

# Update system packages
update_system() {
    log "Updating system packages..."
    apt update && apt upgrade -y
    log "System packages updated"
}

# Install required packages
install_packages() {
    log "Installing required packages..."
    # Base packages always installed
    PACKAGES="git ssh rsyslog ufw curl apt-transport-https gnupg lsb-release ca-certificates"
    
    # Add WireGuard packages if enabled
    if [ "$WG_ENABLED" = true ]; then
        PACKAGES="$PACKAGES wireguard wireguard-tools"
    fi
    
    apt install -y $PACKAGES
    log "Required packages installed"
}

# Set up logging
setup_logging() {
    log "Setting up logging directory..."
    mkdir -p /etc/log
    touch /etc/log/auth.log
    chmod 640 /etc/log/auth.log

    log "Configuring rsyslog for auth logging..."
    cat > /etc/rsyslog.d/90-auth.conf << EOF
auth,authpriv.*                 /etc/log/auth.log
EOF

    # Add symlink from standard location for compatibility
    if [ ! -L /var/log/auth.log ]; then
        ln -sf /etc/log/auth.log /var/log/auth.log
    fi

    # Restart rsyslog service
    systemctl restart rsyslog
    log "Logging setup completed"
}

# Create user droid with predefined password
create_user() {
    if ! id -u droid &>/dev/null; then
        log "Creating user 'droid' with predefined password..."
        useradd -m -s /bin/bash droid
        echo "droid:droid" | chpasswd
        log "User 'droid' created with password 'droid'"
    else
        log "User 'droid' already exists, updating password..."
        echo "droid:droid" | chpasswd
        log "Password updated for user 'droid'"
    fi
}

# Configure SSH
configure_ssh() {
    log "Configuring SSH..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

    # Configure SSH 
    cat > /etc/ssh/sshd_config << EOF
# SSH Server Configuration
Port 2222
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes 
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
AllowUsers droid root

# Enhanced logging
SyslogFacility AUTH
LogLevel VERBOSE
EOF

    # Create SSH directory for user droid
    if [ ! -d /home/droid/.ssh ]; then
        mkdir -p /home/droid/.ssh
        touch /home/droid/.ssh/authorized_keys
        chmod 700 /home/droid/.ssh
        chmod 600 /home/droid/.ssh/authorized_keys
    fi

    # Restart SSH service
    log "Restarting SSH service..."
    systemctl restart ssh
    systemctl enable ssh
    log "SSH configuration completed"
}

# Set up WireGuard
setup_wireguard() {
    if [ "$WG_ENABLED" = false ]; then
        log "WireGuard setup skipped (parameters not provided)"
        return 0
    fi

    log "Setting up WireGuard..."

    log "WireGuard public key: $WG_CLIENT_PUBLICKEY"
    log "Make sure to add this public key to your WireGuard server configuration"

    # Create WireGuard configuration file
    cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $WG_CLIENT_PRIVATEKEY
Address = $WG_CLIENT_IP
ListenPort = 51820
DNS = 10.0.0.1
MTU = 1280

[Peer]
PublicKey = $WG_CLIENT_PUBLICKEY
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $WG_SERVER_IP:$WG_SERVER_PORT
PersistentKeepalive = 25
EOF

    # Set proper permissions for WireGuard configuration
    chmod 600 /etc/wireguard/wg0.conf

    # Enable and start WireGuard interface
    log "Enabling WireGuard interface..."
    systemctl enable wg-quick@wg0
    systemctl start wg-quick@wg0
    
    log "Starting WireGuard interface..."
    wg-quick up wg0 || true
    
    log "WireGuard setup completed"
}

# Configure basic firewall
configure_firewall() {
    log "Configuring basic firewall..."
    ufw allow 2222/tcp comment "SSH"
    
    # Add WireGuard rule if enabled
    if [ "$WG_ENABLED" = true ]; then
        ufw allow 51820/udp comment "WireGuard"
    fi
    
    ufw --force enable
    log "Basic firewall configured"
}

# Clone the droid-pkvm repository 
clone_repo() {
    log "Cloning droid-pkvm repository..."
    # Create directory in droid user's home
    mkdir -p /home/droid/droid-pkvm
    
    # Clone the repository
    git clone https://github.com/terranblake/droid-pkvm.git /home/droid/droid-pkvm
    
    log "Repository cloned to /home/droid/droid-pkvm"
}

# Test WireGuard connectivity
test_wireguard() {
    if [ "$WG_ENABLED" = false ]; then
        log "WireGuard testing skipped (not configured)"
        return 0
    fi

    log "Testing WireGuard connectivity..."
    
    # Check if WireGuard interface is up
    if ! ip a show wg0 &>/dev/null; then
        log "ERROR: WireGuard interface (wg0) is not up"
        return 1
    fi
    
    log "WireGuard interface is up"
    
    # Ping the server through WireGuard
    if ping -c 3 -W 5 "$WG_SERVER_IP" &>/dev/null; then
        log "Successfully pinged WireGuard server"
        return 0
    else
        log "WARNING: Failed to ping WireGuard server. Check your configuration"
        return 1
    fi
}

# Test SSH access
test_ssh() {
    log "Testing SSH configuration..."
    
    # Check if SSH service is running
    if ! systemctl is-active --quiet ssh; then
        log "ERROR: SSH service is not running"
        return 1
    fi
    
    log "SSH service is running"
    
    # Check if SSH port is open
    if ss -tuln | grep -q ":2222"; then
        log "SSH port is open and listening"
        return 0
    else
        log "ERROR: SSH port is not open"
        return 1
    fi
}

# Print final summary
print_summary() {
    local ssh_result=$1
    local wg_result=$2
    local host_ip=$(hostname -I | awk '{print $1}')
    
    echo "======================= BOOTSTRAP COMPLETE ======================="
    if [ "$WG_ENABLED" = true ]; then
        echo "WireGuard Public Key: $WG_CLIENT_PUBLICKEY"
        echo "WireGuard Status: $([ $wg_result -eq 0 ] && echo 'WORKING' || echo 'FAILED')"
    else
        echo "WireGuard: NOT CONFIGURED (parameters not provided)"
        echo "You can still access the VM directly via SSH without WireGuard."
    fi
    echo ""
    echo "SSH Status: $([ $ssh_result -eq 0 ] && echo 'WORKING' || echo 'FAILED')"
    echo ""
    echo "Access Information:"
    echo "- SSH: ssh droid@$host_ip -p 2222 (password: droid)"
    echo ""
    echo "Next Steps:"
    echo "1. Run the setup script from the VM to complete the installation:"
    echo "   cd ~/droid-pkvm"
    echo "   ./setup.sh"
    echo ""
    echo "Authentication logs are being written to: /etc/log/auth.log"
    echo "================================================================"
}

# Main execution
main() {
    log "Starting Android pKVM bootstrap script"
    
    if [ "$WG_ENABLED" = true ]; then
        log "WireGuard will be configured with provided parameters"
    else
        log "WireGuard setup will be skipped (parameters not provided)"
    fi
    
    check_root
    update_system
    install_packages
    setup_logging
    create_user
    configure_ssh
    setup_wireguard
    configure_firewall
    clone_repo
    
    # Run tests
    test_ssh
    SSH_RESULT=$?
    
    if [ "$WG_ENABLED" = true ]; then
        test_wireguard
        WG_RESULT=$?
    else
        WG_RESULT=0
    fi
    
    # Print summary
    print_summary $SSH_RESULT $WG_RESULT
    
    log "Bootstrap completed!"
}

# Run the main function
main