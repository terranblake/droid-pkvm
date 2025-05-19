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
  
  document.getElementById('dashboard-link').href = `http://${hostIp}:${dashboardPort}`;
  document.getElementById('glances-link').href = `http://${hostIp}:${glancesPort}`;
}

// Load hardware info into the page
function loadHardwareInfo() {
  fetch('hardware/cpuinfo.txt')
    .then(response => response.text())
    .then(data => {
      document.getElementById('cpu-info').innerHTML = `<h3>CPU Information</h3><pre>${data}</pre>`;
    })
    .catch(error => {
      document.getElementById('cpu-info').innerHTML = '<p>Error loading CPU information</p>';
    });
}

// Load Android evidence
function loadAndroidEvidence() {
  fetch('hardware/android_evidence.html')
    .then(response => response.text())
    .then(data => {
      document.getElementById('android-evidence').innerHTML = data;
    })
    .catch(error => {
      document.getElementById('android-evidence').innerHTML = '<p>Error loading Android evidence</p>';
    });
}

// Initialize the page
document.addEventListener('DOMContentLoaded', function() {
  updateDashboardUrls();
  loadHardwareInfo();
  loadAndroidEvidence();
}); 