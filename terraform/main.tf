# Data source to find Ubuntu 24.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  ami_id = var.ubuntu_ami != "" ? var.ubuntu_ami : data.aws_ami.ubuntu.id
}

# Generate SSH key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh.public_key_openssh
}

# Save private key locally
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/../state/${var.key_name}.pem"
  file_permission = "0600"
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Subnet (for VM0 - staging with internet access)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

# Private Subnet (for VM1, VM2, VM3 - air-gapped)
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# Route Table for Private Subnet (no internet route - air-gapped)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# Security Group for VM0 (Staging - internet access)
resource "aws_security_group" "staging" {
  name        = "${var.project_name}-staging-sg"
  description = "Security group for staging server (VM0)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.allowed_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-staging-sg"
  }
}

# Security Group for Air-Gapped VMs (VM1, VM2, VM3)
resource "aws_security_group" "airgapped" {
  name        = "${var.project_name}-airgapped-sg"
  description = "Security group for air-gapped servers"
  vpc_id      = aws_vpc.main.id

  # SSH from allowed IP
  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.allowed_cidr]
  }

  # Kibana UI from allowed IP
  ingress {
    description = "Kibana UI from allowed IP"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = [local.allowed_cidr]
  }

  # Elasticsearch from within security group
  ingress {
    description = "Elasticsearch from security group"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    self        = true
  }

  # Package Registry from within security group
  ingress {
    description = "Package Registry from security group"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    self        = true
  }

  # Artifact Registry from within security group
  ingress {
    description = "Artifact Registry from security group"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    self        = true
  }

  # Fleet Server from within security group
  ingress {
    description = "Fleet Server from security group"
    from_port   = 8220
    to_port     = 8220
    protocol    = "tcp"
    self        = true
  }

  # Allow all traffic within the security group (for internal communication)
  ingress {
    description = "All traffic from security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # No internet egress (air-gapped)
  egress {
    description = "Allow traffic within VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.project_name}-airgapped-sg"
  }
}

# VM0: Staging Server (internet-connected)
resource "aws_instance" "vm0_staging" {
  ami                    = local.ami_id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.generated.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.staging.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/vm0-setup.sh", {
    elastic_version = var.elastic_version
  })

  tags = {
    Name = "${var.project_name}-vm0-staging"
    Role = "staging"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = self.public_ip
  }

  # Wait for setup script to complete
  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for VM0 setup to complete...'",
      "while [ ! -f /home/ubuntu/.vm0-setup-complete ]; do sleep 30; echo 'Still waiting...'; done",
      "echo 'VM0 setup complete!'"
    ]
  }
}

# VM1: Registries Server (air-gapped)
resource "aws_instance" "vm1_registries" {
  ami                    = local.ami_id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.generated.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.airgapped.id]

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
  }

  user_data = file("${path.module}/scripts/vm1-setup.sh")

  tags = {
    Name = "${var.project_name}-vm1-registries"
    Role = "registries"
  }
}

# VM2: Elastic Stack Server (air-gapped)
resource "aws_instance" "vm2_elastic" {
  ami                    = local.ami_id
  instance_type          = "t3.large"
  key_name               = aws_key_pair.generated.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.airgapped.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = file("${path.module}/scripts/vm2-setup.sh")

  tags = {
    Name = "${var.project_name}-vm2-elastic"
    Role = "elastic-stack"
  }
}

# VM3: Fleet Server (air-gapped)
resource "aws_instance" "vm3_fleet" {
  ami                    = local.ami_id
  instance_type          = "t3.medium"
  key_name               = aws_key_pair.generated.key_name
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.airgapped.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = file("${path.module}/scripts/vm3-setup.sh")

  tags = {
    Name = "${var.project_name}-vm3-fleet"
    Role = "fleet-server"
  }
}

# Transfer bundle from VM0 to air-gapped VMs and wait for setup completion
resource "null_resource" "transfer_bundle" {
  depends_on = [
    aws_instance.vm0_staging,
    aws_instance.vm1_registries,
    aws_instance.vm2_elastic,
    aws_instance.vm3_fleet,
    local_file.private_key
  ]

  # Transfer bundle to VM1
  provisioner "local-exec" {
    command = <<-EOT
      echo "Transferring bundle to VM1..."
      scp -i ${local_file.private_key.filename} -o StrictHostKeyChecking=no \
        ubuntu@${aws_instance.vm0_staging.public_ip}:/home/ubuntu/airgap-bundle.tar \
        ubuntu@${aws_instance.vm1_registries.public_ip}:/home/ubuntu/
    EOT
  }

  # Transfer bundle to VM2
  provisioner "local-exec" {
    command = <<-EOT
      echo "Transferring bundle to VM2..."
      scp -i ${local_file.private_key.filename} -o StrictHostKeyChecking=no \
        ubuntu@${aws_instance.vm0_staging.public_ip}:/home/ubuntu/airgap-bundle.tar \
        ubuntu@${aws_instance.vm2_elastic.public_ip}:/home/ubuntu/
    EOT
  }

  # Transfer bundle to VM3
  provisioner "local-exec" {
    command = <<-EOT
      echo "Transferring bundle to VM3..."
      scp -i ${local_file.private_key.filename} -o StrictHostKeyChecking=no \
        ubuntu@${aws_instance.vm0_staging.public_ip}:/home/ubuntu/airgap-bundle.tar \
        ubuntu@${aws_instance.vm3_fleet.public_ip}:/home/ubuntu/
    EOT
  }

  # Wait for VM1 setup to complete
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = aws_instance.vm1_registries.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for VM1 setup to complete...'",
      "while [ ! -f /home/ubuntu/.vm1-setup-complete ]; do sleep 10; done",
      "echo 'VM1 setup complete!'"
    ]
  }
}

# Wait for VM2 setup to complete
resource "null_resource" "wait_vm2" {
  depends_on = [null_resource.transfer_bundle]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = aws_instance.vm2_elastic.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for VM2 setup to complete...'",
      "while [ ! -f /home/ubuntu/.vm2-setup-complete ]; do sleep 10; done",
      "echo 'VM2 setup complete!'"
    ]
  }
}

# Wait for VM3 setup to complete
resource "null_resource" "wait_vm3" {
  depends_on = [null_resource.transfer_bundle]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = aws_instance.vm3_fleet.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for VM3 setup to complete...'",
      "while [ ! -f /home/ubuntu/.vm3-setup-complete ]; do sleep 10; done",
      "echo 'VM3 setup complete!'"
    ]
  }
}
