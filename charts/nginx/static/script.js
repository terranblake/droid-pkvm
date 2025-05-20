function toggleHardware() {
  var content = document.getElementById('hardware-content');
  if (content.style.display === 'block') {
    content.style.display = 'none';
  } else {
    content.style.display = 'block';
  }
}

function toggleEvidence() {
  var content = document.getElementById('evidence-content');
  if (content.style.display === 'block') {
    content.style.display = 'none';
  } else {
    content.style.display = 'block';
  }
}

// Get IP address from the current URL
function getHostIpFromUrl() {
  return window.location.hostname;
}

// Update dashboard URLs
function updateDashboardUrls() {
  const hostIp = getHostIpFromUrl();
  // We'll get the actual port values from the template
  const dashboardPort = DASHBOARD_PORT;
  const glancesPort = GLANCES_PORT;
  
  document.getElementById('kubernetes-link').href = `http://${hostIp}:${dashboardPort}`;
  document.getElementById('glances-link').href = `http://${hostIp}:${glancesPort}`;
}

// Load Android evidence
function loadAndroidEvidence() {
  fetch('hardware/android_evidence_dashboard.html')
    .then(response => response.text())
    .then(data => {
      document.getElementById('android-evidence').innerHTML = data;
    })
    .catch(error => {
      // Fallback to regular evidence file if dashboard version not found
      fetch('hardware/android_evidence.html')
        .then(response => response.text())
        .then(data => {
          document.getElementById('android-evidence').innerHTML = data;
        })
        .catch(err => {
          document.getElementById('android-evidence').innerHTML = 
            '<p>Error loading Android evidence. Please run detect_android.sh on the VM.</p>';
        });
    });
}

// Initialize the page
document.addEventListener('DOMContentLoaded', function() {
  updateDashboardUrls();
  loadAndroidEvidence();
}); 