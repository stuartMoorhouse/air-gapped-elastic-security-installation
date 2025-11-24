#!/bin/bash
set -e

# VM2 Setup Script - Elastic Stack Server (Air-Gapped)
# This script waits for the bundle and extracts it.

LOG_FILE="/var/log/vm2-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VM2 Setup Started at $(date) ==="

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

echo "=== VM2 Setup Completed at $(date) ==="
echo "Bundle extracted. Ready for Elasticsearch and Kibana installation."
echo "Continue with Part D Step 2 in the guide."

# Create completion marker
touch /home/ubuntu/.vm2-setup-complete
