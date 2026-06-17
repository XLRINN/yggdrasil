provider "proxmox" {
  endpoint = "https://asgard:8006/"
  username = "root@pam"
  password = var.proxmox_password
  insecure = true

  ssh {
    username = "root"
    password = var.proxmox_password
    agent    = false

    node {
      name    = "asgard"
      address = "asgard"
    }
  }
}

# Pi-hole LXC
resource "proxmox_virtual_environment_container" "pihole" {
  node_name    = "asgard"
  vm_id        = 102
  unprivileged = true

  initialization {
    hostname = "pihole"

    ip_config {
      ipv4 {
        address = "192.168.69.2/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_account {
      password = var.proxmox_password
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
    nesting = true
  }

  startup {
    order = 1
  }

  provisioner "local-exec" {
    when    = create
    command = "ssh-keygen -R 192.168.69.2 || true"
  }
}

resource "null_resource" "pihole_post_create" {
  depends_on = [proxmox_virtual_environment_container.pihole]

  connection {
    type     = "ssh"
    host     = "asgard"
    user     = "root"
    password = var.proxmox_password
  }

  provisioner "remote-exec" {
    inline = [
      "pct exec 102 -- mkdir -p /root/.ssh",
      "pct exec 102 -- chmod 700 /root/.ssh",
      "echo '${var.ssh_public_key}' | pct exec 102 -- tee /root/.ssh/authorized_keys",
      "pct exec 102 -- chmod 600 /root/.ssh/authorized_keys",
    ]
  }
}

# Cloudflared + Homepage LXC
# Privileged required for Docker (Homepage runs as a Docker container)
resource "proxmox_virtual_environment_container" "cloudflared" {
  node_name    = "asgard"
  vm_id        = 103
  unprivileged = false

  initialization {
    hostname = "cloudflared"

    ip_config {
      ipv4 {
        address = "192.168.69.3/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_account {
      password = var.proxmox_password
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 512
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
    nesting = true
    keyctl  = true  # required for Docker in LXC
  }

  startup {
    order = 2
  }

  provisioner "local-exec" {
    when    = create
    command = "ssh-keygen -R 192.168.69.3 || true"
  }
}

resource "null_resource" "cloudflared_post_create" {
  depends_on = [proxmox_virtual_environment_container.cloudflared]

  connection {
    type     = "ssh"
    host     = "asgard"
    user     = "root"
    password = var.proxmox_password
  }

  provisioner "remote-exec" {
    inline = [
      "pct exec 103 -- mkdir -p /root/.ssh",
      "pct exec 103 -- chmod 700 /root/.ssh",
      "echo '${var.ssh_public_key}' | pct exec 103 -- tee /root/.ssh/authorized_keys",
      "pct exec 103 -- chmod 600 /root/.ssh/authorized_keys",
    ]
  }
}
