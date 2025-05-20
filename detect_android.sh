#!/bin/bash

# Android pKVM Detection Script
# This script collects information that could confirm the VM is running on an Android device
# It is mainly used for testing and verification

OUTPUT_FILE="android_evidence.txt"

echo "===== Android pKVM Detection Report =====" > $OUTPUT_FILE
echo "Date: $(date)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Check kernel version (focus on AVF indicators)
echo "== Kernel Information ==" >> $OUTPUT_FILE
KERNEL_VERSION=$(uname -a)
echo "$KERNEL_VERSION" >> $OUTPUT_FILE
if echo "$KERNEL_VERSION" | grep -q "avf"; then
    echo "FOUND: Android Virtualization Framework (AVF) kernel detected" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check /proc/version
echo "== System Version ==" >> $OUTPUT_FILE
PROC_VERSION=$(cat /proc/version)
echo "$PROC_VERSION" >> $OUTPUT_FILE
if echo "$PROC_VERSION" | grep -q "avf"; then
    echo "FOUND: Android Virtualization Framework (AVF) kernel detected in proc/version" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for Android mounts
echo "== Android Mount Points ==" >> $OUTPUT_FILE
ANDROID_MOUNTS=$(cat /proc/mounts | grep -i "android")
if [ -n "$ANDROID_MOUNTS" ]; then
    echo "$ANDROID_MOUNTS" >> $OUTPUT_FILE
    echo "FOUND: Android filesystem mount points detected" >> $OUTPUT_FILE
else
    echo "No Android-specific mount points found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for kernel extras directory
echo "== Android Virtualization Framework Kernel Extras ==" >> $OUTPUT_FILE
if [ -d "/opt/kernel_extras" ]; then
    echo "FOUND: Kernel extras directory exists" >> $OUTPUT_FILE
    
    # Check for AVF kernel
    if ls /opt/kernel_extras/dtbs 2>/dev/null | grep -q "avf"; then
        echo "FOUND: AVF kernel dtbs:" >> $OUTPUT_FILE
        ls -la /opt/kernel_extras/dtbs 2>/dev/null >> $OUTPUT_FILE
    fi
    
    if ls /opt/kernel_extras/headers 2>/dev/null | grep -q "avf"; then
        echo "FOUND: AVF kernel headers:" >> $OUTPUT_FILE
        ls -la /opt/kernel_extras/headers 2>/dev/null >> $OUTPUT_FILE
    fi
    
    if ls /opt/kernel_extras/modules 2>/dev/null | grep -q "avf"; then
        echo "FOUND: AVF kernel modules:" >> $OUTPUT_FILE
        ls -la /opt/kernel_extras/modules 2>/dev/null >> $OUTPUT_FILE
    fi
else
    echo "Kernel extras directory not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for Android-specific properties
echo "== Android Properties ==" >> $OUTPUT_FILE
if command -v getprop &> /dev/null; then
    echo "FOUND: getprop command exists - definitive proof of Android" >> $OUTPUT_FILE
    getprop >> $OUTPUT_FILE
else
    echo "getprop command not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for /system directory structure (Android-specific)
echo "== Android System Structure ==" >> $OUTPUT_FILE
if [ -d "/system" ]; then
    echo "FOUND: /system directory exists (Android indicator)" >> $OUTPUT_FILE
    ls -la /system >> $OUTPUT_FILE
    
    if [ -f "/system/build.prop" ]; then
        echo "FOUND: Android build.prop file" >> $OUTPUT_FILE
        grep -i "ro.product" /system/build.prop >> $OUTPUT_FILE
    fi
else
    echo "/system directory not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for Android shared mount
echo "== Android Shared Mount ==" >> $OUTPUT_FILE
if [ -d "/mnt/shared" ]; then
    echo "FOUND: /mnt/shared directory exists (Android virtiofs mount)" >> $OUTPUT_FILE
    # Don't try to list contents as it may not be supported
    echo "Note: Contents listing skipped as virtiofs operation may not be supported" >> $OUTPUT_FILE
else
    echo "/mnt/shared directory not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for Android driver directories
echo "== Android Driver Directories ==" >> $OUTPUT_FILE
DRIVERS_PATH="/usr/lib/modules/$(uname -r)/kernel/drivers/android"
if [ -d "$DRIVERS_PATH" ]; then
    echo "FOUND: Android drivers directory exists" >> $OUTPUT_FILE
    ls -la "$DRIVERS_PATH" >> $OUTPUT_FILE
else
    echo "Android drivers directory not found at expected path" >> $OUTPUT_FILE
    # Find alternative locations
    ANDROID_DRIVERS=$(find /usr/lib/modules -name "android" -type d 2>/dev/null)
    if [ -n "$ANDROID_DRIVERS" ]; then
        echo "FOUND: Android drivers in alternative location:" >> $OUTPUT_FILE
        echo "$ANDROID_DRIVERS" >> $OUTPUT_FILE
    fi
fi
echo "" >> $OUTPUT_FILE

# Check for Android headers
echo "== Android Headers ==" >> $OUTPUT_FILE
if [ -d "/usr/include/linux/android" ]; then
    echo "FOUND: Android kernel headers exist" >> $OUTPUT_FILE
    ls -la /usr/include/linux/android >> $OUTPUT_FILE
else
    echo "Android kernel headers not found at expected path" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check for KVM/Hypervisor info
echo "== Virtualization Information ==" >> $OUTPUT_FILE
if command -v lscpu &> /dev/null; then
    VIRT_INFO=$(lscpu | grep -i "virtualization\|hyper")
    echo "$VIRT_INFO" >> $OUTPUT_FILE
    if [ -n "$VIRT_INFO" ]; then
        echo "FOUND: Virtualization technology detected" >> $OUTPUT_FILE
    fi
else
    echo "lscpu command not found" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Check dmesg for pKVM references
echo "== pKVM Evidence in dmesg ==" >> $OUTPUT_FILE
if [ "$(id -u)" -eq 0 ]; then
    PKVM_DMESG=$(dmesg | grep -i "pkvm\|protected\|hypervisor\|avf\|android")
    if [ -n "$PKVM_DMESG" ]; then
        echo "$PKVM_DMESG" >> $OUTPUT_FILE
        echo "FOUND: pKVM/hypervisor references in dmesg" >> $OUTPUT_FILE
    else
        echo "No pKVM/hypervisor references found in dmesg" >> $OUTPUT_FILE
    fi
else
    echo "Note: dmesg requires root privileges. Run with sudo for complete information." >> $OUTPUT_FILE
    # Try with sudo but don't fail if it doesn't work
    sudo dmesg 2>/dev/null | grep -i "pkvm\|protected\|hypervisor\|avf\|android" >> $OUTPUT_FILE 2>&1 || echo "Could not access dmesg output (permission denied)" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Scan for Android references across the filesystem (limited to key directories)
echo "== Android Files and Directories ==" >> $OUTPUT_FILE
echo "Scanning key directories for Android references..." >> $OUTPUT_FILE
ANDROID_FILES=$(find /opt /usr/include /usr/lib -name "*android*" -type f -o -type d 2>/dev/null | head -20)
if [ -n "$ANDROID_FILES" ]; then
    echo "FOUND: Android-related files and directories:" >> $OUTPUT_FILE
    echo "$ANDROID_FILES" >> $OUTPUT_FILE
else
    echo "No Android-related files found in key directories" >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Summarize the most conclusive findings
echo "===== CONCLUSIVE EVIDENCE SUMMARY =====" >> $OUTPUT_FILE
# Initialize counter for conclusive evidence points
EVIDENCE_COUNT=0

# Check if kernel has AVF
if echo "$KERNEL_VERSION $PROC_VERSION" | grep -q "avf"; then
    echo "✓ Running on Android Virtualization Framework (AVF) kernel" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
fi

# Check for Android mounts
if [ -n "$ANDROID_MOUNTS" ]; then
    echo "✓ Android filesystem mounted at: $(echo "$ANDROID_MOUNTS" | awk '{print $2}')" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
fi

# Check for getprop command
if command -v getprop &> /dev/null; then
    echo "✓ Android property system (getprop) available" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
fi

# Check for system directory
if [ -d "/system" ]; then
    echo "✓ Android /system directory exists" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
fi

# Check for shared mount
if [ -d "/mnt/shared" ]; then
    echo "✓ Android shared mount exists at /mnt/shared" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
fi

# Check for Android kernel extras
if [ -d "/opt/kernel_extras" ] && ls /opt/kernel_extras/*/* 2>/dev/null | grep -q "avf"; then
    echo "✓ Android Virtualization Framework kernel extras present" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
fi

# Final conclusion
echo "" >> $OUTPUT_FILE
if [ $EVIDENCE_COUNT -ge 3 ]; then
    echo "CONCLUSION: This is definitely running on Android (found $EVIDENCE_COUNT pieces of conclusive evidence)" >> $OUTPUT_FILE
elif [ $EVIDENCE_COUNT -ge 1 ]; then
    echo "CONCLUSION: This is likely running on Android (found $EVIDENCE_COUNT pieces of evidence)" >> $OUTPUT_FILE
else
    echo "CONCLUSION: Could not definitively determine if this is running on Android" >> $OUTPUT_FILE
fi

echo "" >> $OUTPUT_FILE
echo "File saved to: $OUTPUT_FILE"

# Create a summary HTML version for dashboard display
cat > android_evidence_dashboard.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>Android Evidence</title>
  <style>
    body { font-family: sans-serif; }
    h3 { color: #4CAF50; margin-top: 20px; }
    .evidence-item { 
      background-color: #f5f5f5; 
      padding: 10px; 
      border-radius: 4px; 
      margin-bottom: 10px;
      border-left: 4px solid #4CAF50;
    }
    .conclusion {
      font-weight: bold;
      font-size: 16px;
      margin-top: 20px;
      padding: 10px;
      background-color: #E8F5E9;
      border-radius: 4px;
    }
  </style>
</head>
<body>
<h3>Android Evidence Summary</h3>
EOF

# Add only the conclusive evidence to the dashboard HTML
grep "^✓" $OUTPUT_FILE | while read -r line; do
    echo "<div class='evidence-item'>$line</div>" >> android_evidence_dashboard.html
done

# Add the conclusion
CONCLUSION=$(grep "^CONCLUSION:" $OUTPUT_FILE)
echo "<div class='conclusion'>$CONCLUSION</div>" >> android_evidence_dashboard.html

# Close the HTML
cat >> android_evidence_dashboard.html << EOF
<p><small>For full details, see android_evidence.txt</small></p>
</body>
</html>
EOF

echo "Dashboard summary saved to: android_evidence_dashboard.html" 