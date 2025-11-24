#!/bin/bash
set -e

# VM1 Setup Script - Registries Server (Air-Gapped)
# This script waits for the bundle, extracts it, and installs Docker.

LOG_FILE="/var/log/vm1-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VM1 Setup Started at $(date) ==="

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

# Install Docker from local .deb files
echo "=== Installing Docker from local packages ==="
cd /home/ubuntu/airgap-files/docker-debs
dpkg -i *.deb || apt-get install -f -y
usermod -aG docker ubuntu

echo "=== VM1 Setup Completed at $(date) ==="
echo "Docker installed. Ready for Package Registry and Nginx setup."
echo "Continue with Part C Step 3 in the guide."

# Create completion marker
touch /home/ubuntu/.vm1-setup-complete
