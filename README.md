# Android pKVM Setup

A toolkit for deploying Debian VMs on Android devices with pKVM (protected Kernel Virtual Machine) support. This project demonstrates how to leverage Android's hypervisor capabilities to run fully featured Linux environments with Kubernetes.

![Android pKVM Dashboard View](static/images/dashboard-screenshot.png)

## Purpose

This repository provides a bootstrapping process for Android pKVM instances, making it simple to deploy containerized applications on Android devices with hypervisor support.

## Quick Setup

### 1. Bootstrap the VM

```bash
# On the pKVM instance
curl -O https://raw.githubusercontent.com/terranblake/droid-pkvm/main/bootstrap.sh
chmod +x bootstrap.sh
./bootstrap.sh [wg_server_ip] [wg_server_pubkey] [wg_client_pubkey] [wg_client_privkey]
```

### 2. Configure Services

```bash
# Transfer your SSH key to the VM
scp -P 2222 ~/.ssh/id_ed25519.pub droid@<vm-ip>:~/my_key.pub

# On the VM, run setup
cd ~/droid-pkvm
sudo ./setup.sh ~/my_key.pub
```

### 3. Access

```bash
# Remote SSH access
ssh -i ~/.ssh/your_key -p 2222 droid@<vm-ip>

# Web interfaces (default ports)
Kubernetes Dashboard: http://<vm-ip>:30443
System Monitor (Glances): http://<vm-ip>:8080
Hardware Info: http://<vm-ip>:30081
```

## Features

- Android environment detection
- Optional WireGuard VPN integration
- SSH hardening with key-based authentication
- Kubernetes (k3s) deployment
- Web-based monitoring dashboards

## Documentation

- [Testing Guide](TESTING.md) - Detailed testing procedures and troubleshooting
- [Charts](charts/) - Helm charts for deployed services

## Conclusions

After experimenting with Android pKVM instances, we've observed several key findings:

- **VM Stability**: The VM stability can be inconsistent. Occasionally, the Android OS unmounts the VM filesystem and refuses to remount it. This requires resetting the "Linux Terminal" app, erasing the entire OS. This repository mitigates this issue by providing a quick bootstrap process.

- **Host Performance**: Host devices operate normally while the VM is running, with no unintended restarts. Testing was primarily done on a Pixel Tablet. Storage remains contained within the VM unless external mount points are explicitly defined.

- **Resource Allocation**: 
  - Android 16+ can dedicate almost the entire storage space to the VM
  - Android 16 specifically allocates 4GB of RAM (out of 8GB) to the VM

- **Limitations**: The "Linux Terminal" app, while clean, lacks options for configuring base images or using custom images.

## License

MIT 