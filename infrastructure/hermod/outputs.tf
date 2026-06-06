output "vm_ip" {
  value = var.vm_ip
}

output "vm_name" {
  value = proxmox_virtual_environment_vm.hermod.name
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.hermod.vm_id
}
