locals {
  name_template = join("-", [var.environment, var.module])
}

data "azurerm_resource_group" "docker" {
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
resource "azurerm_public_ip" "docker" {
  count               = var.node_count
  name                = join("-", ["pip", local.name_template, format("%02d", count.index + 1)])
  location            = data.azurerm_resource_group.docker.location
  resource_group_name = data.azurerm_resource_group.docker.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = join("-", ["wan", local.name_template, format("%02d", count.index + 1)])
  tags                = var.tags
}

//Create network interface cards
resource "azurerm_network_interface" "docker" {
  count               = var.node_count
  name                = join("-", ["nic", local.name_template, format("%02d", count.index + 1)])
  location            = data.azurerm_resource_group.docker.location
  resource_group_name = data.azurerm_resource_group.docker.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.docker.*.id, count.index)
  }
}

resource "azurerm_network_interface_security_group_association" "docker" {
  count                     = var.node_count
  network_interface_id      = element(azurerm_network_interface.docker.*.id, count.index)
  network_security_group_id = var.nsg_id
}

resource "azurerm_network_interface_backend_address_pool_association" "docker" {
  count                   = var.be_pool_id != "" ? var.node_count : 0
  backend_address_pool_id = var.be_pool_id
  ip_configuration_name   = "ipconfig"
  network_interface_id    = element(azurerm_network_interface.docker[*].id, count.index)
}

// Create virtual machines
resource "azurerm_virtual_machine" "docker" {
  count                            = var.node_count
  name                             = join("-", ["vm", local.name_template, format("%02d", count.index + 1)])
  location                         = data.azurerm_resource_group.docker.location
  resource_group_name              = data.azurerm_resource_group.docker.name
  network_interface_ids            = [element(azurerm_network_interface.docker.*.id, count.index)]
  vm_size                          = var.node_size
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true
  tags                             = var.tags

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts-gen2"
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
    disable_password_authentication = false
  }
}

resource "null_resource" "provisioners" {
  depends_on = [azurerm_virtual_machine.docker]
  count = var.node_count

  triggers = {
    always = timestamp()
  }
  connection {
    type     = "ssh"
    host     = element(azurerm_public_ip.docker.*.fqdn, count.index)
    user     = var.username
    password = var.password
    timeout  = "3m"
  }
  provisioner "remote-exec" {
    inline = ["date"]
  }

  provisioner "local-exec" {
    command = "cat ./provisioning/ansible/inventory/inventory"
  }
  provisioner "local-exec" {
    command = "sed -i '1i ${join("-", ["host", local.name_template, format("%02d", count.index + 1)])} ansible_ssh_host=${element(azurerm_public_ip.docker.*.fqdn, count.index)}' ./provisioning/ansible/inventory/inventory"
  }
  provisioner "local-exec" {
    command = "sed '/^[docker_nodes]$/a ${join("-", ["host", local.name_template, format("%02d", count.index + 1)])}' ./provisioning/ansible/inventory/inventory"
  }
  provisioner "local-exec" {
    command = "cat ./provisioning/ansible/inventory/inventory"
  }
}