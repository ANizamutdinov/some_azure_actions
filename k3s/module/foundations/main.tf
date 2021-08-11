resource "azurerm_resource_group" "rg" {
  location = var.location
  name     = join("-", ["rg", var.env])
}

resource "azurerm_virtual_network" "vnet" {
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["172.19.0.0/24"]
  name                = join("-", ["vnet", var.name_template])
}

resource "azurerm_subnet" "snet" {
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  name                 = join("-", ["snet", var.name_template])
  address_prefixes     = ["172.19.0.32/27"]
}
