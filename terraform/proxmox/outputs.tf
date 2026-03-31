locals {
  cp_ips = {
    for n in var.control_plane_nodes : n.name => split("/", n.ip_cidr)[0]
  }
  worker_ips = {
    for n in var.worker_nodes : n.name => split("/", n.ip_cidr)[0]
  }
}

output "control_plane_ips" {
  description = "Control plane node name -> IP map"
  value       = local.cp_ips
}

output "worker_ips" {
  description = "Worker node name -> IP map"
  value       = local.worker_ips
}

# Emit a ready-to-use ansible inventory so you can copy it directly.
output "ansible_inventory" {
  description = "Ansible hosts.yml content — pipe to ansible/inventory/hosts.yml"
  value = <<-EOT
all:
  children:
    control_plane:
      hosts:
%{for name, ip in local.cp_ips~}
        ${name}:
          ansible_host: ${ip}
%{endfor~}
    workers:
      hosts:
%{for name, ip in local.worker_ips~}
        ${name}:
          ansible_host: ${ip}
%{endfor~}
  vars:
    ansible_user: ${var.vm_user}
    ansible_ssh_private_key_file: ~/.ssh/id_ed25519
EOT
}
