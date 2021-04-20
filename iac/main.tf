terraform {
  backend "azurerm" {
    storage_account_name = "sumgantfstatelab"
    container_name       = "sumgantfstatecontainer"
    key                  = "labstate.tfstate"
    access_key           = "G+1eOX80lQb+2fXpkEYQQy/RLAP+CZ5IVG4venNwhUArBuymfVW/wavbSYOKbTR2h5RFNng15TdD6AURYq64pw=="
  }
}

provider "azurerm" {
  skip_provider_registration = true
  version                    = "2.55.0"
  features {}
}

locals {
  env           = "dev"
  app           = "app"
  name_template = "${local.env}-${local.app}"
}

resource "azurerm_resource_group" "rg" {
  location = "northeurope"
  name     = join("-", ["rg", local.env])
}

resource "azurerm_virtual_network" "vnet" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["172.19.0.0/24"]
  name                = join("-", ["vnet", local.name_template])
}

module "nsg" {
  source                = "Azure/network-security-group/azurerm"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  security_group_name   = join("-", ["nsg", local.name_template])
  source_address_prefix = ["0.0.0.0/0"]
  predefined_rules = [
    {
      name     = "HTTP"
      priority = "300"
    }
  ]
}

resource "azurerm_subnet" "snet" {
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  name                 = join("-", ["snet", local.name_template])
  address_prefixes     = ["172.19.0.32/27"]
}

resource "azurerm_public_ip" "pip" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  name                = join("-", ["pip", local.name_template])
}

resource "azurerm_network_interface" "nic" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  name                = join("-", ["nic", local.name_template])
  ip_configuration {
    name                          = "ifconfig"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.snet.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_to_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = module.nsg.network_security_group_id
}
resource "azurerm_virtual_machine" "vm" {
  location                         = azurerm_resource_group.rg.location
  name                             = join("-", ["vm", local.name_template])
  network_interface_ids            = [azurerm_network_interface.nic.id]
  resource_group_name              = azurerm_resource_group.rg.name
  vm_size                          = "Standard_B1s"
  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal-daily"
    sku       = "20_04-daily-lts-gen2"
    version   = "latest"
  }

  storage_os_disk {
    name              = join("-", ["osdisk", local.name_template])
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
    disk_size_gb      = 32
  }

  //  storage_data_disk {
  //    create_option = "Empty"
  //    lun           = 0
  //    name          = join("-", ["datadisk", local.name_template])
  //    disk_size_gb  = 32
  //  }
  os_profile {
    admin_username = "sumgan"
    computer_name  = join("-", ["host", local.name_template])
    admin_password = "kuH85mLsWjCFLQdV5Vl"
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      host     = azurerm_public_ip.pip.ip_address
      user     = self.os_profile.*.admin_username
      password = self.os_profile.*.admin_password
      timeout  = "3m"
    }
    inline = ["date"]
  }

  provisioner "local-exec" {
    command = "pwd && ls -l && cat ./apps/provisioning/ansible/inventory/inventory && sed -i 's/{host}/${azurerm_public_ip.pip.ip_address}/g' ./apps/provisioning/ansible/inventory/inventory && cat ./apps/provisioning/ansible/inventory/inventory"
  }
}