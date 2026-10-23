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

resource "proxmox_virtual_environment_container" "vuln" {
  node_name    = "asgard"
  vm_id        = 104
  unprivileged = false # privileged container — required for NFS server

  initialization {
    hostname = "vuln"

    ip_config {
      ipv4 {
        address = "192.168.69.85/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = ["192.168.69.2", "1.1.1.1"]
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
    size         = 32
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
    mount   = ["nfs", "cifs"] # allow NFS and SMB server inside container
  }

  startup {
    order = 1
  }

  provisioner "local-exec" {
    when    = create
    command = "ssh-keygen -R 192.168.69.85 || true"
  }
}


resource "proxmox_virtual_environment_container" "code" {
  node_name    = "asgard"
  vm_id        = 105
  unprivileged = false # privileged container — required to mount alexandria over NFS

  initialization {
    hostname = "code"

    ip_config {
      ipv4 {
        address = "192.168.69.20/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = ["192.168.69.2", "1.1.1.1"]
    }

    user_account {
      password = var.proxmox_password
      keys     = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  cpu {
    cores = 4
  }

  memory {
    dedicated = 4096
    swap      = 0
  }

  disk {
    datastore_id = "disks-fast"
    size         = 32
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
    nesting = true # required for systemd on Ubuntu 24.04
    mount   = ["nfs"] # allow NFS client mount of alexandria
  }

  startup {
    order = 2
  }

  provisioner "local-exec" {
    when    = create
    command = "ssh-keygen -R 192.168.69.20 || true"
  }
}

resource "proxmox_virtual_environment_container" "host" {
  node_name    = "asgard"
  vm_id        = 106
  unprivileged = true

  initialization {
    hostname = "host"

    ip_config {
      ipv4 {
        address = "192.168.69.21/24"
        gateway = var.gateway
      }
    }

    dns {
      servers = ["192.168.69.2", "1.1.1.1"]
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
    dedicated = 2048
    swap      = 0
  }

  disk {
    datastore_id = "disks-fast"
    size         = 16
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
    nesting = true # required for Docker
    keyctl  = true # required for Docker in an unprivileged container
  }

  startup {
    order = 2
  }

  provisioner "local-exec" {
    when    = create
    command = "ssh-keygen -R 192.168.69.21 || true"
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

resource "null_resource" "vuln_post_create" {
  depends_on = [proxmox_virtual_environment_container.vuln]

  connection {
    type     = "ssh"
    host     = "asgard"
    user     = "root"
    password = var.proxmox_password
  }

  

  provisioner "remote-exec" {
    inline = [
      # Inject SSH key directly into container filesystem
      "pct exec 104 -- mkdir -p /root/.ssh",
      "pct exec 104 -- chmod 700 /root/.ssh",
      "echo '${var.ssh_public_key}' | pct exec 104 -- tee /root/.ssh/authorized_keys",
      "pct exec 104 -- chmod 600 /root/.ssh/authorized_keys",
      # Add TUN device for Tailscale
      "grep -q 'dev/net/tun' /etc/pve/lxc/104.conf || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/104.conf",
      "grep -q 'dev/net/tun' /etc/pve/lxc/104.conf || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file 0 0' >> /etc/pve/lxc/104.conf",
      "pct reboot 104"
    ]
  }
}

resource "null_resource" "code_post_create" {
  depends_on = [proxmox_virtual_environment_container.code]

  connection {
    type     = "ssh"
    host     = "asgard"
    user     = "root"
    password = var.proxmox_password
  }

  provisioner "remote-exec" {
    inline = [
      # Inject SSH key directly into container filesystem
      "pct exec 105 -- mkdir -p /root/.ssh",
      "pct exec 105 -- chmod 700 /root/.ssh",
      "echo '${var.ssh_public_key}' | pct exec 105 -- tee /root/.ssh/authorized_keys",
      "pct exec 105 -- chmod 600 /root/.ssh/authorized_keys",
      # Add TUN device for Tailscale
      "grep -q 'dev/net/tun' /etc/pve/lxc/105.conf || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/105.conf",
      "grep -q 'dev/net/tun' /etc/pve/lxc/105.conf || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file 0 0' >> /etc/pve/lxc/105.conf",
      "pct reboot 105"
    ]
  }
}

resource "null_resource" "host_post_create" {
  depends_on = [proxmox_virtual_environment_container.host]

  connection {
    type     = "ssh"
    host     = "asgard"
    user     = "root"
    password = var.proxmox_password
  }

  provisioner "remote-exec" {
    inline = [
      # Inject SSH key directly into container filesystem
      "pct exec 106 -- mkdir -p /root/.ssh",
      "pct exec 106 -- chmod 700 /root/.ssh",
      "echo '${var.ssh_public_key}' | pct exec 106 -- tee /root/.ssh/authorized_keys",
      "pct exec 106 -- chmod 600 /root/.ssh/authorized_keys",
      # Add TUN device for Tailscale
      "grep -q 'dev/net/tun' /etc/pve/lxc/106.conf || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/106.conf",
      "grep -q 'dev/net/tun' /etc/pve/lxc/106.conf || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file 0 0' >> /etc/pve/lxc/106.conf",
      "pct reboot 106"
    ]
  }
}
