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

# Create the NAT network
resource "libvirt_network" "k8s_net" {
  name   = "k8s-net"
  mode   = "nat"
  bridge = "virbr-k8s"
  domain = "k8s.local"

  # NAT outbound traffic
  addresses = ["192.168.122.0/24"]

  dhcp {
    enabled = true
  }

  # TODO: specify dns.hosts using node variables
  dns {
    enabled = true
    hosts {
      hostname = "control-01"
      ip       = "192.168.122.2"
    }
    hosts {
      hostname = "worker-01"
      ip       = "192.168.122.3"
    }
  }

  # Ensure the network survives host reboot
  # autostart = true
}

# We fetch the ubuntu release image from their mirrors
resource "libvirt_volume" "ubuntu_server" {
  name   = "ubuntu-server"
  source = "./ubuntu-24.04-server-cloudimg-amd64.img" # local image resized to 40GB
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
resource "libvirt_domain" "domains" {
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
    network_name = "k8s-net"
  }

  graphics {}
}
