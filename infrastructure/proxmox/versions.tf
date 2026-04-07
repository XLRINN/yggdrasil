terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.17"
    }
  }
  required_version = ">= 1.5.0"
}
