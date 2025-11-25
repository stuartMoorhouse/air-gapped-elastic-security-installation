# Elastic Security Air-Gapped Deployment Guide

---

## Overview
An air-gapped Elastic Security installation requires hosting three critical services locally that would normally be accessed over the internet: the *Elastic Package Registry* (which provides integration packages that Kibana needs to configure data collection), the *Elastic Artifact Registry* (which provides Elastic Agent binaries for installation and upgrades), and optionally the *Elastic Endpoint Artifact Repository* (which provides security artifacts for Elastic Defend). Since the air-gapped network has no internet access, all software packages, Docker images, and binaries must be downloaded on an internet-connected machine and transferred into the environment before installation can begin.

This guide provides instructions in how to deploy Elastic Security with Elastic Agent and self-managed Fleet Server in an air-gapped environment. 

As an example, a test deployment using AWS EC2 instances is provided.

---

## VM Requirements for test deployment

You need **FOUR** separate VMs to complete the test deployment. VM0 is used to download files and can be terminated after transferring files to the air-gapped VMs.

| VM Name | Purpose | Instance Type | Storage | Internet | Ports |
|---------|---------|---------------|---------|----------|-------|
| **VM0: Staging** | Download files, transfer to air-gap | t3.medium | 100GB gp3 | YES | 22 |
| VM1: Registries | Package Registry, Artifact Registry | t3.medium | 100GB gp3 | NO | 22, 8080, 8081 |
| VM2: Elastic Stack | Elasticsearch, Kibana | t3.large | 50GB gp3 | NO | 22, 9200, 5601 |
| VM3: Fleet Server | Fleet Server, Test Agent | t3.medium | 30GB gp3 | NO | 22, 8220 |

**Important:** All VMs should use Ubuntu 24.04 LTS. VM0 needs full internet access. VM1, VM2, and VM3 should have NO internet access (simulating the air-gapped environment). In AWS testing, you can simulate this by not attaching an Internet Gateway to their subnet, or by using restrictive Security Groups.

---

### AWS Security Group Rules

Create a Security Group with these inbound rules:

| Type | Port | Source | Purpose |
|------|------|--------|---------|
| SSH | 22 | Your IP | SSH access |
| Custom TCP | 5601 | Your IP | Kibana UI |
| Custom TCP | 9200 | Security Group | Elasticsearch |
| Custom TCP | 8080 | Security Group | Package Registry |
| Custom TCP | 8081 | Security Group | Artifact Registry |
| Custom TCP | 8220 | Security Group | Fleet Server |

---

# STEP 0: Automated Setup with Terraform (Optional)

> **Skip this step** if you are manually provisioning VMs or deploying in a real air-gapped environment. Proceed directly to Part A.

For AWS testing, Terraform can automate infrastructure provisioning and file staging. When `terraform apply` completes, skip to **Part C Step 3**.

## What Terraform Automates

| Step | Description |
|------|-------------|
| Infrastructure | VMs, VPC, Security Groups, SSH key pair |
| Part A (all steps) | Install Docker on VM0, download files, create archive |
| Part B | Transfer bundle to VM1, VM2, VM3 |
| Part C Steps 1-2 | Extract archive on VM1, install Docker |
| Part D Step 1 | Extract archive on VM2 |
| Part F Step 1 | Extract archive on VM3 |

## Prerequisites

- AWS credentials in environment (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
- `MY_IP` environment variable set to your public IP address

## Run Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Optionally edit terraform.tfvars to customize settings

terraform init
terraform apply --auto-approve
```

Terraform will:
1. Generate an SSH key pair (saved to `../state/elastic-airgap-key.pem`)
2. Create all infrastructure (VMs, VPC, security groups)
3. Wait for VM0 to download all files (~15-20 minutes)
4. Transfer the bundle to VM1, VM2, VM3
5. Wait for all VMs to extract and set up

## After Terraform Completes

The output will show SSH commands and IP addresses. Use these to connect to VMs:

```bash
# Example output
ssh -i ../state/elastic-airgap-key.pem ubuntu@<VM1_IP>
```

**Skip to Part C Step 3** to continue with manual configuration.

---

# PART A: Download Files on Internet-Connected VM

> **If you completed Step 0:** Skip this entire section. Proceed to Part C Step 3.

SSH into VM0 (the staging server with internet access) and run all commands in this section. This VM downloads everything needed for the air-gapped deployment.

## Step 1: Update the System

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

## Step 2: Install Docker

Run each command one at a time:

```bash
sudo apt-get install ca-certificates curl gnupg -y
```

```bash
sudo install -m 0755 -d /etc/apt/keyrings
```

```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
```

```bash
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

```bash
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

```bash
sudo apt-get update
```

```bash
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
```

```bash
sudo usermod -aG docker $USER
```

```bash
newgrp docker
```

## Step 3: Create Staging Directory

```bash
mkdir -p ~/airgap-files
```

```bash
cd ~/airgap-files
```

## Step 4: Download and Save Package Registry Docker Image

Pull the Docker image (approximately 15GB, this will take several minutes):

```bash
docker pull docker.elastic.co/package-registry/distribution:9.2.0
```

Save the image to a file:

```bash
docker save -o package-registry-9.2.0.tar docker.elastic.co/package-registry/distribution:9.2.0
```

Verify the file was created:

```bash
ls -lh package-registry-9.2.0.tar
```

## Step 5: Download Elastic Agent Binaries

Set the version variable:

```bash
export VERSION=9.2.0
```

Create directories for the artifacts:

```bash
mkdir -p downloads/beats/elastic-agent
mkdir -p downloads/fleet-server
mkdir -p downloads/endpoint-dev
```

Download Elastic Agent files:

```bash
cd ~/airgap-files/downloads/beats/elastic-agent
```

```bash
curl -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-linux-x86_64.tar.gz
```

```bash
curl -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-linux-x86_64.tar.gz.sha512
```

```bash
curl -O https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${VERSION}-linux-x86_64.tar.gz.asc
```

Download Fleet Server files:

```bash
cd ~/airgap-files/downloads/fleet-server
```

```bash
curl -O https://artifacts.elastic.co/downloads/fleet-server/fleet-server-${VERSION}-linux-x86_64.tar.gz
```

```bash
curl -O https://artifacts.elastic.co/downloads/fleet-server/fleet-server-${VERSION}-linux-x86_64.tar.gz.sha512
```

```bash
curl -O https://artifacts.elastic.co/downloads/fleet-server/fleet-server-${VERSION}-linux-x86_64.tar.gz.asc
```

Download Endpoint Security files:

```bash
cd ~/airgap-files/downloads/endpoint-dev
```

```bash
curl -O https://artifacts.elastic.co/downloads/endpoint-dev/endpoint-security-${VERSION}-linux-x86_64.tar.gz
```

```bash
curl -O https://artifacts.elastic.co/downloads/endpoint-dev/endpoint-security-${VERSION}-linux-x86_64.tar.gz.sha512
```

```bash
curl -O https://artifacts.elastic.co/downloads/endpoint-dev/endpoint-security-${VERSION}-linux-x86_64.tar.gz.asc
```

## Step 6: Download Elasticsearch and Kibana .deb Packages

```bash
cd ~/airgap-files
```

```bash
curl -O https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${VERSION}-amd64.deb
```

```bash
curl -O https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${VERSION}-amd64.deb.sha512
```

```bash
curl -O https://artifacts.elastic.co/downloads/kibana/kibana-${VERSION}-amd64.deb
```

```bash
curl -O https://artifacts.elastic.co/downloads/kibana/kibana-${VERSION}-amd64.deb.sha512
```

## Step 7: Download Docker .deb Packages for Offline Installation

Download Docker packages so they can be installed on VM1 without internet:

```bash
mkdir -p ~/airgap-files/docker-debs
```

```bash
cd ~/airgap-files/docker-debs
```

```bash
apt-get download docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

```bash
apt-get download iptables libip6tc2 libltdl7 pigz libslirp0 slirp4netns
```

## Step 8: Download Nginx Package

```bash
cd ~/airgap-files
```

```bash
apt-get download nginx nginx-common libnginx-mod-http-geoip2 libnginx-mod-http-image-filter libnginx-mod-http-xslt-filter libnginx-mod-mail libnginx-mod-stream libnginx-mod-stream-geoip2
```

## Step 9: Verify All Downloads

```bash
cd ~/airgap-files
```

```bash
ls -lhR
```

You should see the Docker image tar file, the downloads directory with artifacts, and the .deb packages.

## Step 10: Create VM-Specific Archives for Transfer

Create separate archives for each VM to minimize transfer sizes:

**VM1 bundle (Registries - Package Registry + Artifact Registry):**

```bash
cd ~/airgap-files
```

```bash
tar -cvf ~/vm1-bundle.tar package-registry-9.2.0.tar downloads/ docker-debs/ nginx*.deb libnginx*.deb
```

**VM2 bundle (Elastic Stack - Elasticsearch + Kibana only):**

```bash
tar -cvf ~/vm2-bundle.tar elasticsearch-9.2.0-amd64.deb elasticsearch-9.2.0-amd64.deb.sha512 kibana-9.2.0-amd64.deb kibana-9.2.0-amd64.deb.sha512
```

**VM3 bundle (Fleet Server - Elastic Agent only):**

```bash
tar -cvf ~/vm3-bundle.tar downloads/beats/elastic-agent/
```

Check the sizes:

```bash
cd ~
ls -lh vm1-bundle.tar vm2-bundle.tar vm3-bundle.tar
```

---

# PART B: Transfer Files to Air-Gapped VMs

> **If you completed Step 0:** Skip this entire section. Proceed to Part C Step 3.

Transfer the downloaded files from VM0 to the air-gapped VMs. In a real air-gapped environment, you would use a USB drive or approved file transfer mechanism. For AWS testing, we use SCP.

## Option 1: Using SCP (for AWS Testing)

From your local machine (not VM0), run these commands. Replace the IP addresses and key file path:

**Transfer to VM1 (Registries):**

```bash
scp -i your-key.pem ubuntu@VM0_PUBLIC_IP:~/vm1-bundle.tar ubuntu@VM1_PUBLIC_IP:~/
```

**Transfer to VM2 (Elastic Stack):**

```bash
scp -i your-key.pem ubuntu@VM0_PUBLIC_IP:~/vm2-bundle.tar ubuntu@VM2_PUBLIC_IP:~/
```

**Transfer to VM3 (Fleet Server):**

```bash
scp -i your-key.pem ubuntu@VM0_PUBLIC_IP:~/vm3-bundle.tar ubuntu@VM3_PUBLIC_IP:~/
```

## Option 2: Using Intermediate Download (Alternative)

If direct SCP between VMs is not possible, download to your local machine first, then upload to each VM:

```bash
# Download from VM0 to local machine
scp -i your-key.pem ubuntu@VM0_PUBLIC_IP:~/vm1-bundle.tar .
scp -i your-key.pem ubuntu@VM0_PUBLIC_IP:~/vm2-bundle.tar .
scp -i your-key.pem ubuntu@VM0_PUBLIC_IP:~/vm3-bundle.tar .

# Upload to each air-gapped VM
scp -i your-key.pem vm1-bundle.tar ubuntu@VM1_PUBLIC_IP:~/
scp -i your-key.pem vm2-bundle.tar ubuntu@VM2_PUBLIC_IP:~/
scp -i your-key.pem vm3-bundle.tar ubuntu@VM3_PUBLIC_IP:~/
```

## Option 3: Real Air-Gapped Environment (Production)

In a true air-gapped environment:

- Copy airgap-bundle.tar to an approved removable media (USB drive, DVD)
- Follow your organization's data transfer procedures
- Physically transfer the media to the air-gapped network
- Copy files to each server from the removable media

---

# PART C: VM1 - Registries Server Setup (Air-Gapped)

SSH into VM1 and run all commands in this section. This VM has NO internet access.

> **If you completed Step 0:** Skip to Step 3. Steps 1-2 were automated.

## Step 1: Extract the Transfer Archive

```bash
cd ~
```

```bash
tar -xvf vm1-bundle.tar
```

## Step 2: Install Docker from Local .deb Files

```bash
cd ~/docker-debs
```

```bash
sudo dpkg -i *.deb
```

If you see dependency errors, run:

```bash
sudo apt-get install -f
```

Add your user to the docker group:

```bash
sudo usermod -aG docker $USER
```

```bash
newgrp docker
```

## Step 3: Load the Package Registry Docker Image

```bash
cd ~
```

```bash
docker load -i package-registry-9.2.0.tar
```

Verify the image was loaded:

```bash
docker images
```

You should see `docker.elastic.co/package-registry/distribution` with tag `9.2.0`.

## Step 4: Run the Package Registry Container

```bash
docker run -d --name package-registry -p 8080:8080 --restart unless-stopped docker.elastic.co/package-registry/distribution:9.2.0
```

Verify it is running:

```bash
docker ps
```

Test the Package Registry:

```bash
curl http://localhost:8080/health
```

## Step 5: Install Nginx from Local .deb Files

```bash
cd ~
```

```bash
sudo dpkg -i nginx*.deb libnginx*.deb
```

If you see dependency errors, you may need to install them manually or skip the optional modules:

```bash
sudo dpkg -i --force-depends nginx-common*.deb nginx_*.deb
```

## Step 6: Set Up the Artifact Directory Structure

```bash
sudo mkdir -p /var/www/artifacts/downloads
```

```bash
sudo cp -r ~/downloads/* /var/www/artifacts/downloads/
```

```bash
sudo chown -R www-data:www-data /var/www/artifacts
```

```bash
sudo chmod -R 755 /var/www/artifacts
```

## Step 7: Configure Nginx

Create the Nginx configuration file:

```bash
sudo vim /etc/nginx/sites-available/artifacts
```

Paste the following content:

```nginx
server {
    listen 8081;
    server_name _;
    root /var/www/artifacts;
    location / {
        autoindex on;
        etag on;
        add_header Cache-Control "public, max-age=3600";
    }
}
```

Save and exit: Press `Ctrl+X`, then `Y`, then `Enter`.

## Step 8: Enable the Site and Restart Nginx

```bash
sudo ln -s /etc/nginx/sites-available/artifacts /etc/nginx/sites-enabled/
```

```bash
sudo nginx -t
```

```bash
sudo systemctl restart nginx
```

```bash
sudo systemctl enable nginx
```

## Step 9: Verify Artifact Registry

```bash
curl -I http://localhost:8081/downloads/beats/elastic-agent/elastic-agent-9.2.0-linux-x86_64.tar.gz
```

You should see a 200 OK response.

## Step 10: Record VM1 Private IP

```bash
hostname -I | awk '{print $1}'
```

**Write this IP address down. You will use it when configuring Kibana and other VMs.**

---

# PART D: VM2 - Elastic Stack Setup (Air-Gapped)

SSH into VM2 and run all commands in this section. This VM has NO internet access.

> **If you completed Step 0:** Skip to Step 2. Step 1 was automated.

## Step 1: Extract the Transfer Archive

```bash
cd ~
```

```bash
tar -xvf vm2-bundle.tar
```

## Step 2: Verify SHA512 Checksums

```bash
sha512sum -c elasticsearch-9.2.0-amd64.deb.sha512
```

```bash
sha512sum -c kibana-9.2.0-amd64.deb.sha512
```

Both should show 'OK'.

## Step 3: Install Elasticsearch

```bash
sudo dpkg -i elasticsearch-9.2.0-amd64.deb
```

> **IMPORTANT:** After installation, the terminal displays the elastic user password. Copy and save this password immediately!

## Step 4: Start Elasticsearch

```bash
sudo systemctl daemon-reload
```

```bash
sudo systemctl enable elasticsearch
```

```bash
sudo systemctl start elasticsearch
```

Wait about 30 seconds, then verify:

```bash
sudo systemctl status elasticsearch
```

## Step 5: Install Kibana

```bash
sudo dpkg -i kibana-9.2.0-amd64.deb
```

## Step 6: Configure Kibana for Air-Gapped Environment

Edit the Kibana configuration file:

```bash
sudo vim /etc/kibana/kibana.yml
```

Add these lines at the end (replace `VM1_PRIVATE_IP` and `VM2_PUBLIC_IP` with actual values):

```yaml
server.host: "0.0.0.0"
server.publicBaseUrl: "http://VM2_PUBLIC_IP:5601"
xpack.fleet.registryUrl: "http://VM1_PRIVATE_IP:8080"
xpack.fleet.isAirGapped: true
xpack.encryptedSavedObjects.encryptionKey: "something_at_least_32_characters_long"
```

> **Note:** The `encryptionKey` must be at least 32 characters. Generate a random string or use a password generator. This key is required for Fleet to store API keys securely.

Save and exit: Press `Ctrl+X`, then `Y`, then `Enter`.

## Step 7: Start Kibana

```bash
sudo systemctl enable kibana
```

```bash
sudo systemctl start kibana
```

## Step 8: Connect Kibana to Elasticsearch

Generate an enrollment token:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

Copy the token. Open a web browser and go to:

```
http://VM2_PUBLIC_IP:5601
```

Paste the enrollment token when prompted. Then get the verification code:

```bash
sudo /usr/share/kibana/bin/kibana-verification-code
```

Enter the 6-digit code in the browser. Log in with:

- **Username:** `elastic`
- **Password:** The password from Step 3

## Step 9: Record VM2 Private IP

```bash
hostname -I | awk '{print $1}'
```

**Write this IP address down for Fleet Server configuration.**

---

# PART E: Configure Fleet Settings in Kibana

These steps are performed in the Kibana web interface.

## Step 1: Configure Agent Binary Download

1. In Kibana, click the hamburger menu (three lines) in the top left
2. Scroll down and click "Fleet" under Management
3. Click "Settings" tab
4. Scroll to "Agent Binary Download"
5. Click "Add agent binary source"
6. Name: "Local Artifact Registry"
7. URL: `http://VM1_PRIVATE_IP:8081`
8. Check "Make this the default"
9. Click "Save"

---

# PART F: VM3 - Fleet Server Setup (Air-Gapped)

SSH into VM3 and run all commands in this section. This VM has NO internet access.

> **If you completed Step 0:** Skip to Step 2. Step 1 was automated.

## Step 1: Extract the Transfer Archive

```bash
cd ~
```

```bash
tar -xvf vm3-bundle.tar
```

## Step 2: Extract Elastic Agent

```bash
cd ~/downloads/beats/elastic-agent
```

```bash
tar -xzf elastic-agent-9.2.0-linux-x86_64.tar.gz
```

```bash
cd elastic-agent-9.2.0-linux-x86_64
```

## Step 3: Create Fleet Server Policy in Kibana

In the Kibana web interface:

1. Go to Fleet > Agent policies
2. Click "Create agent policy"
3. Name: "Fleet Server Policy"
4. Click "Create agent policy"
5. Click on "Fleet Server Policy"
6. Click "Add integration"
7. Search "Fleet Server", select it
8. Click "Add Fleet Server"
9. Click "Save and continue"

## Step 4: Generate Service Token (on VM2)

SSH to VM2 and run:

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/fleet-server fleet-server-token
```

Fix the file permissions (required for Elasticsearch to read the token file):

```bash
sudo chown elasticsearch:elasticsearch /etc/elasticsearch/service_tokens
sudo chmod 640 /etc/elasticsearch/service_tokens
```

Restart Elasticsearch and Kibana to load the new token:

```bash
sudo systemctl restart elasticsearch
```

Wait for Elasticsearch to start (about 30-60 seconds):

```bash
sudo systemctl status elasticsearch
```

Then restart Kibana:

```bash
sudo systemctl restart kibana
```

**Copy the token value from the create command output. You will need it in Step 6.**

## Step 5: Copy Elasticsearch CA Certificate

On VM2, display the certificate and its fingerprint:

```bash
sudo cat /etc/elasticsearch/certs/http_ca.crt
```

```bash
sudo openssl x509 -in /etc/elasticsearch/certs/http_ca.crt -noout -fingerprint
```

**Write down the fingerprint (e.g., `SHA1 Fingerprint=12:88:CC:...`). You will use it to verify the certificate was copied correctly.**

Copy the entire certificate output (including `-----BEGIN CERTIFICATE-----` and `-----END CERTIFICATE-----` lines). On VM3:

```bash
sudo mkdir -p /etc/fleet-server/certs
```

```bash
sudo nano /etc/fleet-server/certs/ca.crt
```

Paste the certificate, save and exit.

Verify the certificate was copied correctly by checking the fingerprint matches:

```bash
sudo openssl x509 -in /etc/fleet-server/certs/ca.crt -noout -fingerprint
```

> **Important:** The fingerprint must match exactly. If it doesn't, the certificate was not copied correctly and Fleet Server will fail to connect with a "certificate signed by unknown authority" error.

## Step 6: Get the Fleet Server Policy ID

The `--fleet-server-policy` parameter requires the **policy ID**, not the policy name.

To find the policy ID:
1. In Kibana, go to Fleet > Agent policies
2. Click on "Fleet Server Policy"
3. Look at the URL in your browser - it will show something like:
   `http://your-kibana:5601/app/fleet/policies/abc123-def456-789/...`
4. The policy ID is the UUID after `/policies/` (e.g., `abc123-def456-789`)

## Step 7: Install Fleet Server

On VM3, run (replace placeholders with actual values):

```bash
cd ~/downloads/beats/elastic-agent/elastic-agent-9.2.0-linux-x86_64
```

```bash
sudo ./elastic-agent install \
  --fleet-server-es=https://VM2_PRIVATE_IP:9200 \
  --fleet-server-service-token=YOUR_SERVICE_TOKEN \
  --fleet-server-policy=YOUR_POLICY_ID \
  --fleet-server-es-ca=/etc/fleet-server/certs/ca.crt \
  --fleet-server-port=8220
```

> **Important:** Use the policy ID (UUID) from Step 6, not the policy name. Using the policy name (e.g., "Fleet Server Policy" or "fleet-server-policy") will cause the installation to fail with a timeout error.

Type 'y' when prompted.

## Step 8: Verify Fleet Server

```bash
sudo elastic-agent status
```

In Kibana, go to Fleet > Agents. The Fleet Server should show as "Healthy".

## Step 9: Configure Fleet Server Host in Kibana

1. In Kibana, go to Fleet > Settings
2. Under "Fleet Server hosts", click "Edit hosts"
3. Add: `https://VM3_PRIVATE_IP:8220`
4. Click "Save"

---

# PART G: Verification

Verify all components are working.

## From VM2, Check Package Registry

```bash
curl http://VM1_PRIVATE_IP:8080/health
```

## From VM2, Check Artifact Registry

```bash
curl -I http://VM1_PRIVATE_IP:8081/downloads/beats/elastic-agent/elastic-agent-9.2.0-linux-x86_64.tar.gz
```

## From VM2, Check Elasticsearch

```bash
curl -k -u elastic:YOUR_PASSWORD https://localhost:9200/_cluster/health
```

## In Kibana, Check Fleet Server

Go to Fleet > Agents. Fleet Server should show "Healthy" with green status.

---

# PART H: Cleanup

After successful deployment:

- Terminate VM0 (staging server) - it is no longer needed
- Delete bundle files and extracted directories from each VM to free disk space:
  - VM1: `rm -rf ~/vm1-bundle.tar ~/package-registry-9.2.0.tar ~/downloads ~/docker-debs ~/nginx*.deb ~/libnginx*.deb`
  - VM2: `rm -rf ~/vm2-bundle.tar ~/*.deb`
  - VM3: `rm -rf ~/vm3-bundle.tar ~/downloads`
- Review and tighten Security Group rules as needed

---

# Troubleshooting

## Docker Container Not Starting

```bash
docker logs package-registry
```

## Nginx Not Starting

```bash
sudo nginx -t
```

```bash
sudo systemctl status nginx
```

## Elasticsearch Not Starting

```bash
sudo journalctl -u elasticsearch -f
```

## Kibana Not Starting

```bash
sudo journalctl -u kibana -f
```

## Fleet Server Issues

```bash
sudo elastic-agent status
```

```bash
sudo journalctl -u elastic-agent -f
```

## Fleet Server Install Timeout - "Waiting on policy with Fleet Server integration"

If the Fleet Server installation times out with messages like:
```
Fleet Server - Waiting on policy with Fleet Server integration: fleet-server-policy
Error: fleet-server failed: timed out waiting for Fleet Server to start after 2m0s
```

This means you used the **policy name** instead of the **policy ID**. The `--fleet-server-policy` parameter requires the UUID, not the name.

**Solution:**
1. In Kibana, go to Fleet > Agent policies
2. Click on your Fleet Server policy
3. Copy the policy ID from the browser URL (e.g., `6d72ad6f-2315-4e24-ba27-2bec9ee5de6b`)
4. Re-run the install command with the UUID:
   ```bash
   sudo ./elastic-agent install \
     --fleet-server-es=https://VM2_PRIVATE_IP:9200 \
     --fleet-server-service-token=YOUR_TOKEN \
     --fleet-server-policy=6d72ad6f-2315-4e24-ba27-2bec9ee5de6b \
     --fleet-server-es-ca=/path/to/ca.crt \
     --fleet-server-port=8220
   ```

## Reset Elasticsearch Password

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u elastic
```

## Regenerate Kibana Enrollment Token

```bash
sudo /usr/share/elasticsearch/bin/elasticsearch-create-enrollment-token -s kibana
```

## Kibana Cannot Connect to Package Registry

Verify the Package Registry is accessible from VM2:

```bash
curl http://VM1_PRIVATE_IP:8080/health
```

Check Kibana logs for registry connection errors:

```bash
sudo journalctl -u kibana | grep -i registry
```
