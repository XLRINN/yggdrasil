terraform {
    required_version = ">= 1.3.0"
    required_providers {
        proxmox = {
            source  = "telmate/proxmox"
            version = ">= 2.10.0"
        }
    }
}

variable "pm_api_url" {
    description = "Proxmox API URL, e.g. https://proxmox.example.com:8006/api2/json"
    type        = string
}

variable "pm_api_token_id" {
    description = "Proxmox API token id (user@realm!tokenname)"
    type        = string
}

variable "pm_api_token_secret" {
    description = "Proxmox API token secret"
    type        = string
}  

provider "proxmox" {
    pm_api_url         = var.pm_api_url
    pm_api_token_id    = var.pm_api_token_id
    pm_api_token_secret= var.pm_api_token_secret
}