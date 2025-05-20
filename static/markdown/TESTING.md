# Testing Android pKVM

This document provides guidance on testing the setup and verifying whether the VM is genuinely running on an Android device with pKVM.

## Testing the Setup

> **CRITICAL STEP:** Between bootstrap and setup phases, you MUST copy your SSH public key to the VM.
> ```bash
> # From your local machine
> scp -P 2222 ~/.ssh/id_ed25519.pub droid@<vm-ip>:~/my_key.pub
> 
> # Then on the VM, use this key in the setup script
> sudo ./setup.sh ~/my_key.pub
> ```
> Failing to provide a valid SSH key will result in authentication failures.

### 1. Testing Bootstrap and Initial Setup

Use these commands to verify the bootstrap phase was successful:

```bash
# Check SSH service is running
systemctl status ssh

# Verify WireGuard is running (if configured)
ip a show wg0

# Check firewall status
sudo ufw status

# Verify Git repository access
cd ~/droid-pkvm
git status
```

### 2. Testing Kubernetes Setup

Verify Kubernetes components are working properly:

```bash
# Check node status
kubectl get nodes

# Check running pods
kubectl get pods --all-namespaces

# Check services
kubectl get svc --all-namespaces
```

### 3. Testing Web Services

Verify the deployed web services are accessible:

```bash
# Get the VM's IP address
ip addr

# Check ports are open
ss -tuln | grep -E "30443|8080|30081"

# Navigate to these URLs in a browser:
# - Dashboard: http://<vm-ip>:30443
# - Glances: http://<vm-ip>:8080
# - Nginx: http://<vm-ip>:30081
```

## Verifying the Android Environment

## Automatic Detection

The easiest way to check is by running the included detection script:

```bash
./utils/detect_android.sh
```

This will create a file `android_evidence.txt` with detailed information about the environment.

## Manual Checks

You can also perform these checks manually:

### 1. Check for Android Properties

The presence of the `getprop` command and Android properties is the most definitive proof:

```bash
# Check if the command exists
which getprop

# List all Android properties
getprop
```

### 2. Check for Android Directory Structure

Android systems have specific directories:

```bash
# Check for /system directory (Android-specific)
ls -la /system

# Check for /vendor directory (common in Android)
ls -la /vendor

# Check for Android build properties
cat /system/build.prop
```

### 3. Check Kernel and System Version

```bash
# Check kernel version for Android markers
uname -a
cat /proc/version | grep -i android
```

### 4. Check for pKVM Evidence

```bash
# Look for pKVM or hypervisor indicators in dmesg
dmesg | grep -i "pkvm\|protected\|hypervisor"
```

### 5. Check CPU and Virtualization Info

```bash
# Get CPU model and virtualization information
grep "model name" /proc/cpuinfo
lscpu | grep -i "virtualization\|hyper"
```

## Interpreting Results

- **Definitive proof**: Presence of `getprop` command, `/system/build.prop`, or Android properties
- **Strong indicators**: References to Android in kernel version or process listing
- **Supporting evidence**: pKVM references in dmesg or specific hardware configurations

## Web Dashboard

After setup, the Nginx web dashboard will display all collected evidence under the "Android Environment Evidence" section. This provides a user-friendly way to verify the environment.

## Troubleshooting Tests

### 1. SSH Connection Issues

If you cannot connect via SSH:

```bash
# Verify SSH port is open
ss -tuln | grep 2222

# Check SSH service status
systemctl status ssh

# Check SSH config
cat /etc/ssh/sshd_config | grep -i "port\|passwordauth\|pubkeyauth"

# Check authorized keys
cat ~/.ssh/authorized_keys
```

> **SSH Key Transfer Verification:** Ensure your SSH key was properly transferred to the VM before running the setup script. A common issue is providing an invalid or non-existent key path, which breaks SSH authentication.
> 
> If you need to fix SSH after a failed setup:
> ```bash
> # Login with password (if still enabled)
> ssh -p 2222 droid@<vm-ip>
> 
> # Fix the authorized_keys file
> cp ~/.ssh/droid_pkvm.pub ~/.ssh/authorized_keys
> chmod 600 ~/.ssh/authorized_keys
> ```

### 2. Git Repository Issues

If you encounter Git errors about "dubious ownership":

```bash
# Fix repository permissions
sudo git config --global --add safe.directory /home/droid/droid-pkvm
chmod -R 777 ~/droid-pkvm

# Verify Git config
git config --list | grep safe
```

### 3. Filesystem Issues

If you encounter read-only filesystem errors:

```bash
# Check if root is mounted read-only
mount | grep " / "

# Check system logs for filesystem errors
dmesg | grep -i "ext4\|filesystem\|remount"

# Run filesystem check (should be done in recovery mode or after reboot)
sudo e2fsck -fy /dev/vda1
```

### 4. Network Issues

```bash
# Check network interfaces
ip addr

# Test connectivity
ping -c 3 8.8.8.8

# Check DNS resolution
nslookup google.com

# If using WireGuard, check its status
sudo wg show
```