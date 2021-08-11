locals {
  name_template = join("-", [var.environment, var.module])
}

data "azurerm_resource_group" "k3s" {
  name = var.resource_group_name
}

resource "random_string" "disk_naming" {
  length  = 4
  special = false
  number  = false
  upper   = false
  lower   = true
}

//Create Public-IP
resource "azurerm_public_ip" "k3s" {
  count               = var.node_count
  name                = join("-", ["pip", local.name_template, format("%02d", count.index + 1)])
  location            = data.azurerm_resource_group.k3s.location
  resource_group_name = data.azurerm_resource_group.k3s.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = join("-", ["wan", local.name_template, format("%02d", count.index + 1)])
  tags                = var.tags
}

//Create network interface cards
resource "azurerm_network_interface" "k3s" {
  count               = var.node_count
  name                = join("-", ["nic", local.name_template, format("%02d", count.index + 1)])
  location            = data.azurerm_resource_group.k3s.location
  resource_group_name = data.azurerm_resource_group.k3s.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.k3s.*.id, count.index)
  }
}

resource "azurerm_network_interface_security_group_association" "k3s" {
  count                     = var.node_count
  network_interface_id      = element(azurerm_network_interface.k3s.*.id, count.index)
  network_security_group_id = var.nsg_id
}

resource "azurerm_network_interface_backend_address_pool_association" "k3s" {
  count                   = var.be_pool_id != "" ? var.node_count : 0
  backend_address_pool_id = var.be_pool_id
  ip_configuration_name   = "ipconfig"
  network_interface_id    = element(azurerm_network_interface.k3s.*.id, count.index)
}

// Create virtual machines
resource "azurerm_virtual_machine" "k3s" {
  count                            = var.node_count
  name                             = join("-", ["vm", local.name_template, format("%02d", count.index + 1)])
  location                         = data.azurerm_resource_group.k3s.location
  resource_group_name              = data.azurerm_resource_group.k3s.name
  network_interface_ids            = [element(azurerm_network_interface.k3s.*.id, count.index)]
  vm_size                          = var.node_size
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true
  tags                             = var.tags

  storage_image_reference {
    publisher = "Debian"
    offer     = "debian-10-daily"
    sku       = "10-gen2"
    version   = "latest"
  }

  storage_os_disk {
    name              = join("-", ["osdisk", local.name_template, random_string.disk_naming.result, format("%02d", count.index + 1)])
    create_option     = "FromImage"
    caching           = "ReadWrite"
    managed_disk_type = "Standard_LRS"
  }

  dynamic "storage_data_disk" {
    for_each = var.data_disks
    content {
      name              = join("-", ["datadisk", local.name_template, random_string.disk_naming.result, format("%02d", count.index + 1), format("%02d", storage_data_disk.key)])
      lun               = storage_data_disk.key + 10
      create_option     = "Empty"
      disk_size_gb      = storage_data_disk.value
      caching           = "ReadOnly"
      managed_disk_type = var.data_disk_type != "" ? var.data_disk_type : "Premium_LRS"
    }
  }

  os_profile {
    computer_name  = join("-", ["host", local.name_template, format("%02d", count.index + 1)])
    admin_username = var.username
    admin_password = var.password
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("~/.ssh/id_rsa.pub")
      path     = format("/home/%s/.ssh/authorized_keys", var.username)
    }
  }
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = element(azurerm_public_ip.k3s.*.fqdn, count.index)
      user        = var.username
      private_key = file("~/.ssh/id_rsa")
      timeout     = "3m"
    }
    inline = [
      format("echo '%s' | sudo -S -E date", var.password),
      "sudo apt-get update -qq",
      "sudo apt-get upgrade -yqq",
      "sudo apt-get -y install curl htop iftop nload apt-transport-https",
      format("sudo echo \"%s\tALL=(ALL:ALL)\tNOPASSWD:ALL\"| sudo tee -a /etc/sudoers", var.username),
    ]
  }
}
