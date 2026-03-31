provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  username  = var.proxmox_username
  password  = var.proxmox_password
  insecure  = var.proxmox_insecure
}

# ---------------------------------------------------------------------------
# Upload cloud-init user-data snippet to Proxmox snippets storage
# Proxmox must have a storage with "snippets" content enabled (e.g. local).
# ---------------------------------------------------------------------------

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.cluster_name}-cloud-init.yaml"
    data = templatefile("${path.module}/cloud-init/user-data.tpl", {
      vm_user          = var.vm_user
      ssh_public_keys  = var.ssh_public_keys
      cluster_name     = var.cluster_name
    })
  }
}
