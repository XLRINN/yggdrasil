resource "proxmox_virtual_environment_container" "alexandria" {
  node_name    = "asgard"
  vm_id        = 111
  unprivileged = false # privileged container — required for NFS server

  initialization {
    hostname = "alexandria"

    ip_config {
      ipv4 {
        address = "192.168.69.5/24"
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
    path   = "/mnt/mimmis"
  }

  features {
    nesting = true
    mount   = ["nfs", "cifs"] # allow NFS and SMB server inside container
  }

  startup {
    order = 1
  }

  provisioner "local-exec" {
    when    = create
    command = "ssh-keygen -R 192.168.69.5 || true"
  }
}

resource "null_resource" "alexandria_post_create" {
  depends_on = [proxmox_virtual_environment_container.alexandria]

  connection {
    type     = "ssh"
    host     = "asgard"
    user     = "root"
    password = var.proxmox_password
  }

  provisioner "remote-exec" {
    inline = [
      # Inject SSH key directly into container filesystem
      "pct exec 111 -- mkdir -p /root/.ssh",
      "pct exec 111 -- chmod 700 /root/.ssh",
      "echo '${var.ssh_public_key}' | pct exec 111 -- tee /root/.ssh/authorized_keys",
      "pct exec 111 -- chmod 600 /root/.ssh/authorized_keys",
      # Add TUN device for Tailscale
      "grep -q 'dev/net/tun' /etc/pve/lxc/111.conf || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/111.conf",
      "grep -q 'dev/net/tun' /etc/pve/lxc/111.conf || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file 0 0' >> /etc/pve/lxc/111.conf",
      "pct reboot 111"
    ]
  }
}
