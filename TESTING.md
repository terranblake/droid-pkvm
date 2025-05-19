# Testing Android pKVM

This document provides guidance on testing whether the VM is genuinely running on an Android device with pKVM.

## Automatic Detection

The easiest way to check is by running the included detection script:

```bash
./detect_android.sh
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