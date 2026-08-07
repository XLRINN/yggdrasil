variable "proxmox_password" {
  description = "Proxmox root password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key to authorize on LXCs"
  type        = string
  default     = ""
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "192.168.69.1"
}

variable "ubuntu_lxc_template" {
  description = "Proxmox template file ID for Ubuntu 24.04 LXC"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with the account-level 'Access: Apps and Policies' (Edit) permission"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (dashboard → any domain overview → right sidebar)"
  type        = string
}

variable "allowed_emails" {
  description = "Email addresses allowed to sign in to yggdrasil.rip via Google SSO"
  type        = list(string)
}
