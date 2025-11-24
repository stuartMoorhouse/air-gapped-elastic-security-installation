output "ssh_private_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_file.private_key.filename
}

output "vm0_staging_public_ip" {
  description = "Public IP of VM0 (Staging Server)"
  value       = aws_instance.vm0_staging.public_ip
}

output "vm1_registries_public_ip" {
  description = "Public IP of VM1 (Registries Server)"
  value       = aws_instance.vm1_registries.public_ip
}

output "vm1_registries_private_ip" {
  description = "Private IP of VM1 (Registries Server)"
  value       = aws_instance.vm1_registries.private_ip
}

output "vm2_elastic_public_ip" {
  description = "Public IP of VM2 (Elastic Stack Server)"
  value       = aws_instance.vm2_elastic.public_ip
}

output "vm2_elastic_private_ip" {
  description = "Private IP of VM2 (Elastic Stack Server)"
  value       = aws_instance.vm2_elastic.private_ip
}

output "vm3_fleet_public_ip" {
  description = "Public IP of VM3 (Fleet Server)"
  value       = aws_instance.vm3_fleet.public_ip
}

output "vm3_fleet_private_ip" {
  description = "Private IP of VM3 (Fleet Server)"
  value       = aws_instance.vm3_fleet.private_ip
}

output "ssh_commands" {
  description = "SSH commands for connecting to each VM"
  value = <<-EOT
    # SSH to VM0 (Staging - has internet):
    ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.vm0_staging.public_ip}

    # SSH to VM1 (Registries - air-gapped):
    ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.vm1_registries.public_ip}

    # SSH to VM2 (Elastic Stack - air-gapped):
    ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.vm2_elastic.public_ip}

    # SSH to VM3 (Fleet Server - air-gapped):
    ssh -i ${local_file.private_key.filename} ubuntu@${aws_instance.vm3_fleet.public_ip}
  EOT
}

output "kibana_url" {
  description = "URL to access Kibana UI"
  value       = "http://${aws_instance.vm2_elastic.public_ip}:5601"
}

output "important_ips" {
  description = "Important IP addresses for configuration"
  value = <<-EOT
    Use these IPs in your configuration:

    VM1_PRIVATE_IP (for Kibana registry config): ${aws_instance.vm1_registries.private_ip}
    VM2_PUBLIC_IP (for Kibana publicBaseUrl):    ${aws_instance.vm2_elastic.public_ip}
    VM2_PRIVATE_IP (for Fleet Server ES):        ${aws_instance.vm2_elastic.private_ip}
    VM3_PRIVATE_IP (for Fleet Server hosts):     ${aws_instance.vm3_fleet.private_ip}
  EOT
}
