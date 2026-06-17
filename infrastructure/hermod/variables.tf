variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "vm_name" {
  description = "VM hostname"
  type        = string
  default     = "hermod"
}

variable "vm_id" {
  description = "Proxmox VM ID"
  type        = number
  default     = 150
}

variable "cpu_cores" {
  description = "Number of vCPU cores"
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 8192 # 8GB
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 32
}

variable "vm_ip" {
  description = "Static IPv4 address for the VM"
  type        = string
  default     = "192.168.69.50"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.69.1"
}

variable "ssh_public_key" {
  description = "SSH public key to authorize on the VM"
  type        = string
  default     = ""
}
