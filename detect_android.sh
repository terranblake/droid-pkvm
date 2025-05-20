#!/bin/bash

# Android pKVM Detection Script
# This script checks for definitive evidence of running on Android

OUTPUT_FILE="android_evidence.txt"

echo "===== Android pKVM Detection Summary =====" > $OUTPUT_FILE
echo "Date: $(date)" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Initialize evidence counter and array
EVIDENCE_COUNT=0
EVIDENCE_BULLETS=()

# Check for AVF (Android Virtualization Framework) kernel
echo "== Kernel Information ==" >> $OUTPUT_FILE
KERNEL_INFO="$(uname -r) [$(uname -m)]"
echo "Kernel version: $KERNEL_INFO" >> $OUTPUT_FILE

# Function to add evidence
add_evidence() {
    local description="$1"
    echo "FOUND: $description" >> $OUTPUT_FILE
    EVIDENCE_COUNT=$((EVIDENCE_COUNT + 1))
    EVIDENCE_BULLETS+=("$description")
}

# AVF Kernel checks
if uname -a | grep -q "avf"; then
    add_evidence "Android Virtualization Framework (AVF) kernel"
    AVF_FOUND=true
fi

if cat /proc/version 2>/dev/null | grep -q "avf\|android"; then
    if [ "$AVF_FOUND" != "true" ]; then
        add_evidence "Android/AVF signature in /proc/version"
    fi
fi

# Check for Android mounts
ANDROID_MOUNTS=$(cat /proc/mounts 2>/dev/null | grep -i "android")
if [ -n "$ANDROID_MOUNTS" ]; then
    MOUNT_POINT=$(echo "$ANDROID_MOUNTS" | awk '{print $2}')
    add_evidence "Android filesystem mounted at: $MOUNT_POINT"
fi

# Check for Android shared mount
if [ -d "/mnt/shared" ]; then
    SHARED_MOUNT=$(cat /proc/mounts 2>/dev/null | grep "/mnt/shared" | grep "virtiofs")
    if [ -n "$SHARED_MOUNT" ]; then
        add_evidence "Android virtiofs mount at /mnt/shared"
    fi
fi

# Check for Android kernel extras (without verbose listing)
if [ -d "/opt/kernel_extras" ]; then
    AVF_KERNEL=$(find /opt/kernel_extras -name "*avf*" 2>/dev/null | head -1)
    if [ -n "$AVF_KERNEL" ]; then
        add_evidence "AVF kernel components in /opt/kernel_extras"
    fi
fi

# Check for Android-specific properties (most definitive proof)
if command -v getprop &> /dev/null; then
    add_evidence "Android property system (getprop command)"
    
    # Get a few key properties but don't dump all of them
    ANDROID_VERSION=$(getprop ro.build.version.release 2>/dev/null)
    if [ -n "$ANDROID_VERSION" ]; then
        echo "  Android version: $ANDROID_VERSION" >> $OUTPUT_FILE
    fi
fi

# Check for Android system directory with build.prop (strong indicator)
# Note: Just /system by itself isn't sufficient as macOS also has this
if [ -f "/system/build.prop" ]; then
    add_evidence "Android build.prop file in /system directory"
    # Only show product info, not the whole file
    PRODUCT_INFO=$(grep -i "ro.product" /system/build.prop 2>/dev/null | head -2)
    [ -n "$PRODUCT_INFO" ] && echo "  Product info: $PRODUCT_INFO" >> $OUTPUT_FILE
fi

# Check for Android vendor directory
if [ -d "/vendor" ] && [ -f "/vendor/build.prop" ]; then
    add_evidence "Android /vendor directory with build.prop"
fi

# Only check dmesg for specific Android/AVF references 
if [ "$(id -u)" -eq 0 ]; then
    ANDROID_DMESG=$(dmesg 2>/dev/null | grep -i "android\|avf\|protected\|pkvm" | head -3)
    if [ -n "$ANDROID_DMESG" ]; then
        add_evidence "Android/AVF references in kernel messages"
    fi
fi

# Write conclusive summary
echo "" >> $OUTPUT_FILE
echo "===== CONCLUSIVE EVIDENCE SUMMARY =====" >> $OUTPUT_FILE

# Final conclusion
echo "" >> $OUTPUT_FILE
if [ $EVIDENCE_COUNT -ge 3 ]; then
    CONCLUSION="This is definitely running on Android (found $EVIDENCE_COUNT pieces of conclusive evidence)"
elif [ $EVIDENCE_COUNT -ge 1 ]; then
    CONCLUSION="This is likely running on Android (found $EVIDENCE_COUNT pieces of evidence)"
else
    CONCLUSION="No Android evidence found. This is probably not running on Android."
fi

echo "CONCLUSION: $CONCLUSION" >> $OUTPUT_FILE
echo "File saved to: $OUTPUT_FILE" 

# Create a concise HTML version for dashboard display
cat > android_evidence_dashboard.html << EOF
<!DOCTYPE html>
<html>
<head>
  <title>Android Evidence</title>
  <style>
    body { font-family: sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
    h3 { color: #4CAF50; margin-top: 20px; border-bottom: 1px solid #eee; padding-bottom: 8px; }
    .evidence-item { 
      background-color: #f5f5f5; 
      padding: 15px; 
      border-radius: 4px; 
      margin-bottom: 10px;
      border-left: 4px solid #4CAF50;
      font-size: 16px;
    }
    .conclusion {
      font-weight: bold;
      font-size: 18px;
      margin-top: 25px;
      padding: 15px;
      background-color: #E8F5E9;
      border-radius: 4px;
      border-left: 4px solid #388E3C;
    }
    .evidence-count {
      display: inline-block;
      background-color: #4CAF50;
      color: white;
      border-radius: 50%;
      width: 24px;
      height: 24px;
      text-align: center;
      line-height: 24px;
      margin-right: 10px;
    }
    .no-evidence {
      background-color: #f5f5f5;
      padding: 15px;
      border-radius: 4px;
      margin-top: 15px;
      color: #666;
      font-style: italic;
    }
  </style>
</head>
<body>
<h3>Android Evidence Summary</h3>
EOF

# Add evidence bullets to the dashboard
if [ ${#EVIDENCE_BULLETS[@]} -gt 0 ]; then
    for bullet in "${EVIDENCE_BULLETS[@]}"; do
        echo "<div class='evidence-item'>✓ $bullet</div>" >> android_evidence_dashboard.html
    done
else
    echo "<p class='no-evidence'>No conclusive Android evidence was found. This is probably not an Android environment.</p>" >> android_evidence_dashboard.html
fi

# Add the conclusion with evidence count
echo "<div class='conclusion'><span class='evidence-count'>$EVIDENCE_COUNT</span> $CONCLUSION</div>" >> android_evidence_dashboard.html

# Close the HTML
cat >> android_evidence_dashboard.html << EOF
</body>
</html>
EOF

echo "Dashboard summary saved to: android_evidence_dashboard.html" 