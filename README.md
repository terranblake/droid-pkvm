# Android pKVM Setup

This repository contains scripts and configurations to set up a Debian virtual machine running on an Android device with pKVM (protected Kernel Virtual Machine) support. The setup includes optional WireGuard VPN, SSH access, Kubernetes (k3s), and monitoring tools.

## Overview

The setup is split into two main phases:

1. **Bootstrap Phase**: Initial setup on the Android pKVM instance
2. **Post-Bootstrap Phase**: SSH hardening and service deployment

## Requirements

- An Android device with pKVM support
- WireGuard server already set up and configured (optional)
- WireGuard client keypair for the VM (optional)

## Quick Start

### 1. Bootstrap Phase (on the pKVM instance)

```bash
# Download the bootstrap script directly on the pKVM instance
curl -O https://raw.githubusercontent.com/terranblake/droid-pkvm/main/bootstrap.sh
chmod +x bootstrap.sh

# Run the bootstrap script with WireGuard
./bootstrap.sh <wg_server_ip> <wg_server_pubkey> <wg_client_pubkey> <wg_client_privkey>

# Or run without WireGuard
./bootstrap.sh
```

### 2. Post-Bootstrap Phase (on the pKVM instance)

```bash
# Navigate to the cloned repository
cd ~/droid-pkvm

# Run the setup script
./setup.sh [dashboard_port] [glances_port] [nginx_port]
```

### 3. Remote Access

After setup is complete, you can access the pKVM instance from any remote machine:

```bash
# SSH using the generated key (copy the public key from the setup output)
ssh -i ~/.ssh/your_key -p 2222 droid@<pkvm_ip_address>
```

## Detailed Instructions

### Bootstrap Phase

The bootstrap script sets up the basic infrastructure on the pKVM instance:
- WireGuard VPN client (optional)
- SSH server with user 'droid'
- Basic logging and firewall
- Clones this repository

```bash
# With WireGuard VPN
./bootstrap.sh <wg_server_ip> <wg_server_pubkey> <wg_client_pubkey> <wg_client_privkey>

# Without WireGuard VPN
./bootstrap.sh
```

Parameters (all optional):
- `wg_server_ip`: WireGuard server IP address
- `wg_server_pubkey`: WireGuard server's public key
- `wg_client_pubkey`: WireGuard client's public key
- `wg_client_privkey`: WireGuard client's private key

### Post-Bootstrap Phase

The setup script:
- Generates an SSH key and hardens SSH access
- Installs Kubernetes (k3s)
- Installs Helm
- Collects hardware information and runs Android detection
- Deploys Kubernetes Dashboard
- Deploys Glances system monitor
- Deploys Nginx landing page with hardware information

```bash
./setup.sh [dashboard_port] [glances_port] [nginx_port]
```

Parameters (all optional):
- `dashboard_port`: Kubernetes Dashboard port (default: 30443)
- `glances_port`: Glances port (default: 8080)
- `nginx_port`: Nginx port (default: 8081)

## Default Access Information

After setup is complete:

- SSH: `ssh -i ~/.ssh/your_key -p 2222 droid@<pkvm_ip_address>`
- Kubernetes Dashboard: `http://<pkvm_ip_address>:30443`
- Glances: `http://<pkvm_ip_address>:8080`
- Nginx: `http://<pkvm_ip_address>:8081`

The Dashboard token is saved to `~/dashboard-token.txt` on the pKVM instance.

## Verifying Android/pKVM Environment

The setup includes tools to verify whether the VM is indeed running on an Android device with pKVM:

1. The `detect_android.sh` script can be run manually:
   ```bash
   ./detect_android.sh
   ```

2. The Nginx landing page shows all collected hardware information and Android evidence.

The most definitive indicators of Android are:
- Presence of the `getprop` command
- Android-specific directories like `/system` and `/vendor`
- Android build properties in `/system/build.prop`

## Repository Structure

- `bootstrap.sh`: Initial bootstrap script
- `setup.sh`: Post-bootstrap setup script
- `detect_android.sh`: Tool to detect Android environment
- `charts/`: Helm charts for deployed services
  - `glances/`: Glances monitoring tool
  - `nginx/`: Nginx with hardware information dashboard
    - `static/`: Static files for the Nginx dashboard
    - `templates/`: Helm templates
    - `templates/hardware/`: Directory for hardware information
- `TESTING.md`: Detailed testing information

## Troubleshooting

If you encounter issues:

1. **Bootstrap Issues**
   - Verify WireGuard connectivity (if used)
   - Ensure all required parameters are correct
   - Check network access to GitHub

2. **Setup Issues**
   - Verify k3s installation with `kubectl get nodes`
   - Check Helm with `helm version`
   - Review logs with `kubectl logs -n <namespace> <pod-name>`

3. **Service Access Issues**
   - Verify firewall settings with `sudo ufw status`
   - Check service status with `kubectl get svc --all-namespaces`
   - Verify port availability with `ss -tuln`

## License

MIT 