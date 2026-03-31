# ---------------------------------------------------------------------------
# Proxmox connection
# ---------------------------------------------------------------------------

variable "proxmox_endpoint" {
  description = "Proxmox API endpoint URL (e.g. https://192.168.1.100:8006/)"
  type        = string
}

variable "proxmox_username" {
  description = "Proxmox API username (e.g. root@pam or terraform@pve)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification (useful for self-signed certs)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------

variable "proxmox_node" {
  description = "Proxmox node name to deploy VMs on"
  type        = string
  default     = "pve"
}

variable "vm_template_id" {
  description = "Proxmox VM template ID (Ubuntu cloud image, see README)"
  type        = number
  default     = 999
}

variable "storage" {
  description = "Proxmox datastore for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge to attach VMs to"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Default gateway for VM static IPs"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for VMs"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# ---------------------------------------------------------------------------
# VM access
# ---------------------------------------------------------------------------

variable "vm_user" {
  description = "Default user created by cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  description = "List of SSH public keys authorised for the VM user"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Cluster identity
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "Kubernetes cluster name (used in VM hostnames and tags)"
  type        = string
  default     = "yggdrasil"
}

variable "tags" {
  description = "Additional tags to apply to all VMs"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Node definitions
# ---------------------------------------------------------------------------

variable "control_plane_nodes" {
  description = "Control plane node definitions. Use 1 node for single-master or 3 for HA."
  type = list(object({
    name    = string
    vm_id   = number
    ip_cidr = string # e.g. "192.168.1.10/24"
    cores   = optional(number, 2)
    memory  = optional(number, 4096) # MiB
    disk    = optional(number, 40)   # GiB
  }))
  default = [
    {
      name    = "k8s-cp-01"
      vm_id   = 200
      ip_cidr = "192.168.1.10/24"
    }
  ]
}

variable "worker_nodes" {
  description = "Worker node definitions."
  type = list(object({
    name    = string
    vm_id   = number
    ip_cidr = string
    cores   = optional(number, 4)
    memory  = optional(number, 8192) # MiB
    disk    = optional(number, 80)   # GiB
  }))
  default = [
    {
      name    = "k8s-worker-01"
      vm_id   = 211
      ip_cidr = "192.168.1.21/24"
    },
    {
      name    = "k8s-worker-02"
      vm_id   = 212
      ip_cidr = "192.168.1.22/24"
    }
  ]
}
