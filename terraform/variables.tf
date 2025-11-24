variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-north-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "elastic-airgap"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (VM0 - staging)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet (VM1, VM2, VM3 - air-gapped)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH and Kibana access. Defaults to MY_IP env var with /32 suffix."
  type        = string
  default     = ""
}

locals {
  # Use MY_IP environment variable if allowed_ssh_cidr not set
  allowed_cidr = var.allowed_ssh_cidr != "" ? var.allowed_ssh_cidr : "${data.external.my_ip.result.ip}/32"
}

data "external" "my_ip" {
  program = ["bash", "-c", "echo '{\"ip\": \"'$MY_IP'\"}'"]
}

variable "key_name" {
  description = "Name for the SSH key pair to create"
  type        = string
  default     = "elastic-airgap-key"
}

variable "ubuntu_ami" {
  description = "Ubuntu 24.04 LTS AMI ID (leave empty for automatic lookup)"
  type        = string
  default     = ""
}

variable "elastic_version" {
  description = "Elastic Stack version to download"
  type        = string
  default     = "9.2.0"
}
