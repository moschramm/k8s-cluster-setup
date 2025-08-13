terraform {
  required_version = ">= 0.13"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}

# Configure the Libvirt provider
provider "libvirt" {
  uri = "qemu:///system"
}

# We fetch the ubuntu release image from their mirrors
resource "libvirt_volume" "ubuntu_server" {
  name   = "ubuntu-server"
  source = "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
}

# volume to attach to the node's domain as main disk
resource "libvirt_volume" "node_volume" {
  for_each = var.vms

  name           = "node-volume-${each.key}.img"
  base_volume_id = libvirt_volume.ubuntu_server.id
}

resource "libvirt_cloudinit_disk" "commoninit" {
  for_each = var.vms

  name = "commoninit-${each.key}.iso"

  user_data      = file("${path.module}/cloud_init.cfg")
  network_config = file("${path.module}/network_config_${each.value.name}.cfg")
}

# Create the machine
resource "libvirt_domain" "control_domain" {
  for_each = var.vms

  name   = each.value.name
  memory = 8192
  vcpu   = 4

  cloudinit = libvirt_cloudinit_disk.commoninit[each.key].id

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  disk {
    volume_id = libvirt_volume.node_volume[each.key].id
  }

  network_interface {
    bridge = "br0"
  }

  graphics {}
}



# IPs: use wait_for_lease true or after creation use terraform refresh and terraform show for the ips of domain
