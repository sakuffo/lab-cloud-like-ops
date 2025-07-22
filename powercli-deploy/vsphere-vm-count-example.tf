# vSphere VM deployment with count in names

# Method 1: Basic count with vsphere_virtual_machine
resource "vsphere_virtual_machine" "web_servers" {
  count            = 3
  name             = "web-vm-${count.index + 1}"  # Creates: web-vm-1, web-vm-2, web-vm-3
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = "terraform-vms"
  
  num_cpus = 2
  memory   = 4096
  guest_id = "ubuntu64Guest"
  
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  
  disk {
    label = "disk0"
    size  = 20
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}

# Method 2: Environment-specific naming with padding
variable "environment" {
  default = "prod"
}

resource "vsphere_virtual_machine" "app_servers" {
  count            = 5
  name             = format("%s-app-%03d", var.environment, count.index + 1)  # Creates: prod-app-001, prod-app-002, etc.
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  
  num_cpus = 4
  memory   = 8192
  guest_id = "ubuntu64Guest"
  
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  
  disk {
    label = "disk0"
    size  = 40
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    
    customize {
      linux_options {
        host_name = format("%s-app-%03d", var.environment, count.index + 1)
        domain    = "example.local"
      }
      
      network_interface {
        ipv4_address = "10.0.1.${100 + count.index}"
        ipv4_netmask = 24
      }
      
      ipv4_gateway = "10.0.1.1"
    }
  }
}

# Method 3: Using a map for different VM configurations
variable "vm_configs" {
  default = {
    web = {
      count  = 2
      cpu    = 2
      memory = 4096
    }
    app = {
      count  = 3
      cpu    = 4
      memory = 8192
    }
    db = {
      count  = 2
      cpu    = 8
      memory = 16384
    }
  }
}

resource "vsphere_virtual_machine" "multi_tier" {
  for_each = var.vm_configs
  count    = each.value.count
  
  name             = "${each.key}-vm-${count.index + 1}"  # Creates: web-vm-1, app-vm-1, db-vm-1, etc.
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  
  num_cpus = each.value.cpu
  memory   = each.value.memory
  guest_id = "ubuntu64Guest"
  
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  
  disk {
    label = "disk0"
    size  = 40
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}

# Method 4: Sequential naming across multiple datacenters
variable "datacenters" {
  default = ["dc1", "dc2"]
}

resource "vsphere_virtual_machine" "distributed_vms" {
  count            = length(var.datacenters) * 2  # 2 VMs per datacenter
  name             = "vm-${var.datacenters[floor(count.index / 2)]}-${(count.index % 2) + 1}"  # Creates: vm-dc1-1, vm-dc1-2, vm-dc2-1, vm-dc2-2
  resource_pool_id = data.vsphere_compute_cluster.cluster[floor(count.index / 2)].resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore[floor(count.index / 2)].id
  
  num_cpus = 2
  memory   = 4096
  guest_id = "ubuntu64Guest"
  
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  
  disk {
    label = "disk0"
    size  = 20
  }
  
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
}

# Required data sources
data "vsphere_datacenter" "dc" {
  name = "dc1"
}

data "vsphere_datastore" "datastore" {
  name          = "datastore1"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = "cluster1"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = "VM Network"
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = "ubuntu-template"
  datacenter_id = data.vsphere_datacenter.dc.id
}