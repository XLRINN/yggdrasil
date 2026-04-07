resource "proxmox_virtual_environment_container" "alexandria" {
  node_name    = "asgard"
  vm_id        = 111
  unprivileged = false # privileged container — required for NFS server

  initialization {
    hostname = "alexandria"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      password = var.proxmox_password
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 4096
    swap      = 0
  }

  disk {
    datastore_id = "disks-fast"
    size         = 7
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.ubuntu_lxc_template
    type             = "ubuntu"
  }

  mount_point {
    volume = "/mnt/pve/mimmisbrunnr"
    path   = "/alexandria"
  }

  features {
    nesting = true
    mount   = ["nfs", "cifs"] # allow NFS and SMB server inside container
  }

  startup {
    order = 1
  }
}
