terraform {
  //  backend "azurerm" {}
}

provider "azurerm" {
  skip_provider_registration = true
  version = "2.55.0"
  features {}
}

locals {
  env           = "dev"
  app           = "some_app"
  name_template = "${local.env}-${local.app}"
}

resource "azurerm_resource_group" "rg" {
  location = "northeurope"
  name     = join("-", ["rg", local.env])
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
  }
}

resource "azurerm_virtual_machine" "vm" {
  location              = azurerm_resource_group.rg.location
  name                  = join("-", ["vm", local.name_template])
  network_interface_ids = [azurerm_network_interface.nic.id]
  resource_group_name   = azurerm_resource_group.rg.name
  vm_size               = "Standard_B1s"

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
  }

  storage_data_disk {
    create_option = "Empty"
    lun           = 0
    name          = join("-", ["datadisk", local.name_template])
  }
}