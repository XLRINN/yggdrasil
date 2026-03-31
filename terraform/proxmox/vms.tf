locals {
  base_tags    = concat(["k8s", "terraform", var.cluster_name], var.tags)
  cp_nodes     = { for n in var.control_plane_nodes : n.name => n }
  worker_nodes = { for n in var.worker_nodes : n.name => n }
}

# ---------------------------------------------------------------------------
# Control plane nodes
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "control_plane" {
  for_each = local.cp_nodes

  name      = each.value.name
  node_name = var.proxmox_node
  vm_id     = each.value.vm_id
  tags      = concat(local.base_tags, ["control-plane"])

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.storage

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = var.ssh_public_keys
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }

  lifecycle {
    ignore_changes = [
      # Prevent drift from manual Proxmox changes post-deploy
      network_device,
    ]
  }
}

# ---------------------------------------------------------------------------
# Worker nodes
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "worker" {
  for_each = local.worker_nodes

  name      = each.value.name
  node_name = var.proxmox_node
  vm_id     = each.value.vm_id
  tags      = concat(local.base_tags, ["worker"])

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.storage
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.storage

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = var.ssh_public_keys
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }

  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}
