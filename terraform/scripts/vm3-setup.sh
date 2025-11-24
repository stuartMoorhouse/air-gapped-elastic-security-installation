#!/bin/bash
set -e

# VM3 Setup Script - Fleet Server (Air-Gapped)
# This script waits for the bundle and extracts it.

LOG_FILE="/var/log/vm3-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VM3 Setup Started at $(date) ==="

# Wait for bundle to arrive from VM0
echo "=== Waiting for airgap-bundle.tar ==="
while [ ! -f /home/ubuntu/airgap-bundle.tar ]; do
    echo "Waiting for bundle... ($(date))"
    sleep 30
done

echo "=== Bundle received, extracting ==="
cd /home/ubuntu
tar -xvf airgap-bundle.tar
chown -R ubuntu:ubuntu airgap-files/

echo "=== VM3 Setup Completed at $(date) ==="
echo "Bundle extracted. Ready for Fleet Server installation."
echo "Continue with Part F Step 2 in the guide."

# Create completion marker
touch /home/ubuntu/.vm3-setup-complete
