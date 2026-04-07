provider "proxmox" {
  endpoint = "https://asgard:8006/"
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true # self-signed cert
}

resource "proxmox_virtual_environment_vm" "draupnir" {
  name      = var.vm_name
  node_name = "asgard"
  vm_id     = var.vm_id

  clone {
    vm_id        = 999 # ubuntu-cloud template
    full         = true
    retries      = 3
    datastore_id = "disks-fast" # clone disk directly onto target datastore
  }

  cpu {
    cores = var.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = 32768 # 32GB
  }

  disk {
    datastore_id = "disks-fast"
    interface    = "virtio0"
    size         = 128
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.vm_ip}/24"
        gateway = var.gateway
      }
    }

    user_account {
      username = "david"
      password = var.proxmox_password
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }
  }

  operating_system {
    type = "l26"
  }

  agent {
    enabled = false # installed and enabled by Ansible (common role)
  }

  boot_order = ["virtio0"]

  on_boot = true
}
