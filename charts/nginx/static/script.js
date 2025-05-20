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
  const evidenceContainer = document.getElementById('android-evidence');
  evidenceContainer.innerHTML = '<div class="loading">Loading evidence...</div>';
  
  fetch('hardware/android_evidence_dashboard.html')
    .then(response => {
      if (!response.ok) {
        throw new Error('Failed to load dashboard evidence');
      }
      return response.text();
    })
    .then(data => {
      evidenceContainer.innerHTML = data;
    })
    .catch(error => {
      console.error('Error loading dashboard evidence:', error);
      
      // Fallback to regular evidence file if dashboard version not found
      fetch('hardware/android_evidence.html')
        .then(response => {
          if (!response.ok) {
            throw new Error('Failed to load evidence');
          }
          return response.text();
        })
        .then(data => {
          evidenceContainer.innerHTML = data;
        })
        .catch(err => {
          console.error('Error loading evidence:', err);
          evidenceContainer.innerHTML = 
            '<div class="error">Error loading Android evidence. Please run detect_android.sh on the VM.</div>';
        });
    });
}

// Initialize the page
document.addEventListener('DOMContentLoaded', function() {
  updateDashboardUrls();
  loadAndroidEvidence();
  
  // Add event listeners for button hover effects
  const buttons = document.querySelectorAll('.primary-button');
  buttons.forEach(button => {
    button.addEventListener('mouseenter', () => {
      button.style.transition = 'all 0.3s ease';
    });
  });
}); 