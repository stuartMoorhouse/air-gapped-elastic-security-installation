#!/bin/bash
set -e

# VM0 Setup Script - Staging Server
# This script installs Docker, downloads all required files, and creates the archive.
# File transfer to air-gapped VMs must be done manually.

LOG_FILE="/var/log/vm0-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== VM0 Setup Started at $(date) ==="

# Variables (passed via Terraform templatefile)
VERSION="${elastic_version}"

# Step 1: Update system
echo "=== Step 1: Updating system ==="
apt-get update && apt-get upgrade -y

# Step 2: Install Docker
echo "=== Step 2: Installing Docker ==="
apt-get install ca-certificates curl gnupg -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
usermod -aG docker ubuntu

# Step 3: Create staging directory
echo "=== Step 3: Creating staging directory ==="
mkdir -p /home/ubuntu/airgap-files
cd /home/ubuntu/airgap-files

# Step 4: Download and save Package Registry Docker image
echo "=== Step 4: Downloading Package Registry Docker image (this takes several minutes) ==="
docker pull docker.elastic.co/package-registry/distribution:$VERSION
docker save -o package-registry-$VERSION.tar docker.elastic.co/package-registry/distribution:$VERSION

# Step 5: Download Elastic Agent binaries
echo "=== Step 5: Downloading Elastic Agent binaries ==="
mkdir -p downloads/beats/elastic-agent
mkdir -p downloads/fleet-server
mkdir -p downloads/endpoint-dev

cd /home/ubuntu/airgap-files/downloads/beats/elastic-agent
curl -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VERSION-linux-x86_64.tar.gz
curl -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VERSION-linux-x86_64.tar.gz.sha512
curl -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-$VERSION-linux-x86_64.tar.gz.asc

cd /home/ubuntu/airgap-files/downloads/fleet-server
curl -O https://artifacts.elastic.co/downloads/fleet-server/fleet-server-$VERSION-linux-x86_64.tar.gz
curl -O https://artifacts.elastic.co/downloads/fleet-server/fleet-server-$VERSION-linux-x86_64.tar.gz.sha512
curl -O https://artifacts.elastic.co/downloads/fleet-server/fleet-server-$VERSION-linux-x86_64.tar.gz.asc

cd /home/ubuntu/airgap-files/downloads/endpoint-dev
curl -O https://artifacts.elastic.co/downloads/endpoint-dev/endpoint-security-$VERSION-linux-x86_64.tar.gz
curl -O https://artifacts.elastic.co/downloads/endpoint-dev/endpoint-security-$VERSION-linux-x86_64.tar.gz.sha512
curl -O https://artifacts.elastic.co/downloads/endpoint-dev/endpoint-security-$VERSION-linux-x86_64.tar.gz.asc

# Step 6: Download Elasticsearch and Kibana .deb packages
echo "=== Step 6: Downloading Elasticsearch and Kibana packages ==="
cd /home/ubuntu/airgap-files
curl -O https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$VERSION-amd64.deb
curl -O https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-$VERSION-amd64.deb.sha512
curl -O https://artifacts.elastic.co/downloads/kibana/kibana-$VERSION-amd64.deb
curl -O https://artifacts.elastic.co/downloads/kibana/kibana-$VERSION-amd64.deb.sha512

# Step 7: Download Docker .deb packages for offline installation
echo "=== Step 7: Downloading Docker packages for offline installation ==="
mkdir -p /home/ubuntu/airgap-files/docker-debs
cd /home/ubuntu/airgap-files/docker-debs
apt-get download docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
apt-get download iptables libip6tc2 libltdl7 pigz libslirp0 slirp4netns

# Step 8: Download Nginx packages
echo "=== Step 8: Downloading Nginx packages ==="
cd /home/ubuntu/airgap-files
apt-get download nginx nginx-common libnginx-mod-http-geoip2 libnginx-mod-http-image-filter libnginx-mod-http-xslt-filter libnginx-mod-mail libnginx-mod-stream libnginx-mod-stream-geoip2 || true

# Step 9: Create archive
echo "=== Step 9: Creating archive ==="
cd /home/ubuntu
tar -cvf airgap-bundle.tar airgap-files/
chown ubuntu:ubuntu airgap-bundle.tar
chown -R ubuntu:ubuntu airgap-files/

echo "=== VM0 Setup Completed at $(date) ==="
echo ""
echo "Archive created: /home/ubuntu/airgap-bundle.tar"
echo "Size: $(ls -lh /home/ubuntu/airgap-bundle.tar | awk '{print $5}')"
echo ""
echo "Next step: Transfer airgap-bundle.tar to VM1, VM2, and VM3"
echo "See Part B in the guide for transfer instructions."

# Create completion marker
touch /home/ubuntu/.vm0-setup-complete
