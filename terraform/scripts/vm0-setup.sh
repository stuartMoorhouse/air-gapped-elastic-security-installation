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

# Step 9: Create VM-specific archives
echo "=== Step 9: Creating VM-specific archives ==="
cd /home/ubuntu/airgap-files

# VM1 bundle: Package Registry + Artifact downloads + Docker + Nginx
echo "Creating vm1-bundle.tar (Registries)..."
tar -cvf /home/ubuntu/vm1-bundle.tar \
    package-registry-$VERSION.tar \
    downloads/ \
    docker-debs/ \
    nginx*.deb \
    libnginx*.deb 2>/dev/null || tar -cvf /home/ubuntu/vm1-bundle.tar \
    package-registry-$VERSION.tar \
    downloads/ \
    docker-debs/

# VM2 bundle: Elasticsearch + Kibana only
echo "Creating vm2-bundle.tar (Elastic Stack)..."
tar -cvf /home/ubuntu/vm2-bundle.tar \
    elasticsearch-$VERSION-amd64.deb \
    elasticsearch-$VERSION-amd64.deb.sha512 \
    kibana-$VERSION-amd64.deb \
    kibana-$VERSION-amd64.deb.sha512

# VM3 bundle: Elastic Agent only
echo "Creating vm3-bundle.tar (Fleet Server)..."
tar -cvf /home/ubuntu/vm3-bundle.tar \
    downloads/beats/elastic-agent/

cd /home/ubuntu
chown ubuntu:ubuntu vm1-bundle.tar vm2-bundle.tar vm3-bundle.tar
chown -R ubuntu:ubuntu airgap-files/

echo "=== VM0 Setup Completed at $(date) ==="
echo ""
echo "Archives created:"
echo "  vm1-bundle.tar: $(ls -lh /home/ubuntu/vm1-bundle.tar | awk '{print $5}') (Registries)"
echo "  vm2-bundle.tar: $(ls -lh /home/ubuntu/vm2-bundle.tar | awk '{print $5}') (Elastic Stack)"
echo "  vm3-bundle.tar: $(ls -lh /home/ubuntu/vm3-bundle.tar | awk '{print $5}') (Fleet Server)"
echo ""
echo "Next step: Transfer bundles to respective VMs"
echo "See Part B in the guide for transfer instructions."

# Create completion marker
touch /home/ubuntu/.vm0-setup-complete
