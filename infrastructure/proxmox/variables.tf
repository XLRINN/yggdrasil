variable "proxmox_username" {
  description = "Proxmox user"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "VM hostname"
  type        = string
  default     = "draupnir"
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
  default     = 777
}

variable "cpu_cores" {
  description = "Number of vCPU cores"
  type        = number
  default     = 8
}

variable "vm_ip" {
  description = "Static IPv4 address for the VM"
  type        = string
  default     = "192.168.69.77"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.69.1"
}

variable "vm_password" {
  description = "Password for console access (emergency use)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key to authorize on the VM"
  type        = string
  default     = ""
}

variable "ubuntu_lxc_template" {
  description = "Proxmox template file ID for Ubuntu 24.04 LXC"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst"
}

variable "pihole_password" {
  description = "Pi-hole web UI admin password"
  type        = string
  sensitive   = true
}

