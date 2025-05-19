# Android pKVM Setup

This repository contains scripts and configurations to set up a Debian virtual machine running on an Android device with pKVM (protected Kernel Virtual Machine) support. The setup includes WireGuard VPN, SSH access, Kubernetes (k3s), and monitoring tools.

## Overview

The setup is split into two main phases:

1. **Bootstrap Phase**: Initial setup on the Android pKVM instance
2. **Post-Bootstrap Phase**: SSH hardening and service deployment

## Requirements

- An Android device with pKVM support
- WireGuard server already set up and configured
- A machine to run the post-bootstrap setup script

## Bootstrap Phase

The bootstrap script sets up the basic infrastructure on the pKVM instance:

- WireGuard VPN client
- SSH server
- User account (droid)
- Basic logging and firewall

### Usage

```bash
./bootstrap.sh <wg_server_ip> <wg_server_pubkey> <wg_client_pubkey> <wg_client_privkey>
```

Parameters:
- `wg_server_ip`: WireGuard server IP address
- `wg_server_pubkey`: WireGuard server's public key
- `wg_client_pubkey`: WireGuard client's public key
- `wg_client_privkey`: WireGuard client's private key

## Post-Bootstrap Phase

The setup script runs on a separate machine and connects to the pKVM instance to:

- Generate an SSH key and harden SSH access
- Install Kubernetes (k3s)
- Install Helm
- Deploy Kubernetes Dashboard
- Deploy Glances system monitor
- Deploy Nginx landing page with hardware information

### Usage

```bash
./setup.sh <target_host_ip> [ssh_port] [dashboard_port] [glances_port] [nginx_port]
```

Parameters:
- `target_host_ip`: IP address of the pKVM instance
- `ssh_port`: SSH port (default: 2222)
- `dashboard_port`: Kubernetes Dashboard port (default: 30443)
- `glances_port`: Glances port (default: 8080)
- `nginx_port`: Nginx port (default: 8081)

## Default Access Information

After setup is complete:

- SSH: `ssh -i ~/.ssh/droid_pkvm -p 2222 droid@<target_host_ip>`
- Kubernetes Dashboard: `http://<target_host_ip>:30443`
- Glances: `http://<target_host_ip>:8080`
- Nginx: `http://<target_host_ip>:8081`

## Verifying Android/pKVM Environment

The setup includes tools to verify whether the VM is indeed running on an Android device with pKVM. This information is displayed on the Nginx landing page.

## Repository Structure

- `bootstrap.sh`: Initial bootstrap script
- `setup.sh`: Post-bootstrap setup script
- `charts/`: Helm charts for deployed services
  - `glances/`: Glances monitoring tool
  - `nginx/`: Nginx with hardware information dashboard

## Troubleshooting

If you encounter issues:

1. Check WireGuard connectivity
2. Verify SSH access
3. Check k3s and service logs
4. Inspect firewall settings

## License

MIT 