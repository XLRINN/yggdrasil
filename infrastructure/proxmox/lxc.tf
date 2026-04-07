resource "proxmox_virtual_environment_container" "pihole" {
  node_name    = "asgard"
  vm_id        = 100
  unprivileged = true

  initialization {
    hostname = "pihole"

    ip_config {
      ipv4 {
        address = "192.168.69.2/24"
        gateway = "192.168.69.1"
      }
    }

    dns {
      servers = ["1.1.1.1"] # bootstrap — point to itself after provisioning
    }

    user_account {
      password = var.vm_password
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 0
  }

  disk {
    datastore_id = "disks-fast"
    size         = 4
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.ubuntu_lxc_template
    type             = "ubuntu"
  }

  features {
    nesting = true # required for Pi-hole's dnsmasq inside LXC
  }

  on_boot = true
}

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
      password = var.vm_password
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
    mount   = "nfs;cifs" # allow NFS and SMB server inside container
  }

  on_boot = true
}
