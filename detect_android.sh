#!/bin/bash

# Android pKVM Detection Script
# This script collects information that could confirm the VM is running on an Android device
# It is mainly used for testing and verification

OUTPUT_FILE="android_evidence.txt"

echo "===== Android pKVM Detection Report =====" > $OUTPUT_FILE
echo "Date: $(date)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Check kernel version
echo "== Kernel Information ==" >> $OUTPUT_FILE
uname -a >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Check /proc/version
echo "== System Version ==" >> $OUTPUT_FILE
cat /proc/version >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Check for Android-specific properties
echo "== Android Properties ==" >> $OUTPUT_FILE
if command -v getprop &> /dev/null; then
    getprop >> $OUTPUT_FILE
    echo "Found getprop command - this is definitive proof of Android" >> $OUTPUT_FILE
else
    echo "getprop command not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for /system directory structure (Android-specific)
echo "== Android System Structure ==" >> $OUTPUT_FILE
if [ -d "/system" ]; then
    echo "/system directory exists (Android indicator)" >> $OUTPUT_FILE
    ls -la /system >> $OUTPUT_FILE
    
    if [ -f "/system/build.prop" ]; then
        echo "" >> $OUTPUT_FILE
        echo "== Android build.prop file found ==" >> $OUTPUT_FILE
        grep -i "ro.product" /system/build.prop >> $OUTPUT_FILE
    fi
else
    echo "/system directory not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for KVM/Hypervisor info
echo "== Virtualization Information ==" >> $OUTPUT_FILE
if command -v lscpu &> /dev/null; then
    lscpu | grep -i "virtualization\|hyper" >> $OUTPUT_FILE
else
    echo "lscpu command not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check dmesg for pKVM references
echo "== pKVM Evidence in dmesg ==" >> $OUTPUT_FILE
if [ "$(id -u)" -eq 0 ]; then
    dmesg | grep -i "pkvm\|protected\|hypervisor" >> $OUTPUT_FILE 2>&1
else
    echo "Note: dmesg requires root privileges. Run with sudo for complete information." >> $OUTPUT_FILE
    # Try with sudo but don't fail if it doesn't work
    sudo dmesg 2>/dev/null | grep -i "pkvm\|protected\|hypervisor" >> $OUTPUT_FILE 2>&1 || echo "Could not access dmesg output (permission denied)" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for DMI information
echo "== DMI Information ==" >> $OUTPUT_FILE
if [ -d "/sys/class/dmi/id/" ]; then
    echo "Product Name: $(cat /sys/class/dmi/id/product_name 2>/dev/null)" >> $OUTPUT_FILE
    echo "System Vendor: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" >> $OUTPUT_FILE
else
    echo "DMI information not available" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for CPU characteristics
echo "== CPU Information ==" >> $OUTPUT_FILE
grep "model name" /proc/cpuinfo | head -1 >> $OUTPUT_FILE
echo "CPU Cores: $(grep -c "processor" /proc/cpuinfo)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Check for specific Android device indicators
echo "== Additional Evidence ==" >> $OUTPUT_FILE
if [ -d "/vendor" ]; then
    echo "Found /vendor directory (common in Android)" >> $OUTPUT_FILE
    ls -la /vendor >> $OUTPUT_FILE
else
    echo "/vendor directory not found" >> $OUTPUT_FILE
fi

# Summary of findings
echo "" >> $OUTPUT_FILE
echo "===== SUMMARY =====" >> $OUTPUT_FILE
echo "Based on the collected information:" >> $OUTPUT_FILE

if command -v getprop &> /dev/null || [ -f "/system/build.prop" ] || [ -d "/vendor" ]; then
    echo "CONCLUSION: This is definitely running on Android" >> $OUTPUT_FILE
elif grep -qi "android" /proc/version || grep -qi "android" /proc/cpuinfo; then
    echo "CONCLUSION: This is likely running on Android" >> $OUTPUT_FILE
else
    echo "CONCLUSION: Could not definitively determine if this is running on Android" >> $OUTPUT_FILE
fi

echo "" >> $OUTPUT_FILE
echo "File saved to: $OUTPUT_FILE" 