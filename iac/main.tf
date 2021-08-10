terraform {
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id            = var.subscription_id
  client_id                  = var.client_id
  client_secret              = var.client_secret
  tenant_id                  = var.tenant_id
  skip_provider_registration = true
  version                    = "2.70.0"
  features {}
}

locals {
  env           = "dev"
  name_template = join("-", [local.env, "k3s"])
  username      = "sumgan"
  password      = random_string.pass.result
}

resource "random_string" "pass" {
  length  = 19
  upper   = true
  lower   = true
  number  = true
  special = false
}

module "foundations" {
  providers     = { azurerm = azurerm }
  source        = "./module/foundations"
  location      = "westeurope"
  env           = local.env
  name_template = local.name_template
}

module "nsg" {
  providers             = { azurerm = azurerm }
  source                = "Azure/network-security-group/azurerm"
  resource_group_name   = module.foundations.rg.name
  location              = module.foundations.rg.location
  security_group_name   = join("-", ["nsg", local.name_template])
  source_address_prefix = ["0.0.0.0/0"]
  predefined_rules = [
    {
      name     = "SSH"
      priority = "310"
    }
  ]
  custom_rules = [
    {
      name                    = "HTTPS"
      priority                = "330"
      direction               = "Inbound"
      source_address_prefixes = ["0.0.0.0/0"]
      destination_port_range  = "6443"
    }
  ]

}

module "lb" {
  providers           = { azurerm = azurerm }
  source              = "./module/lb"
  resource_group_name = module.foundations.rg.name
  prefix              = local.name_template
  lb_sku              = "Standard"
  type              = "public"
  frontend_name     = join("-", ["lbfe", local.name_template])
  allocation_method = "Static"
  pip_sku           = "Standard"

  lb_port = {
    http = ["6443", "Tcp", "6443"]
  }

  lb_probe = {
    http = ["Tcp", "6443", ""]
  }
}

module "master_pool" {
  providers           = { azurerm = azurerm }
  source              = "./module/k3s_pool"
  resource_group_name = module.foundations.rg.name
  environment         = local.env
  module              = "k3sm"
  subnet_id           = module.foundations.snet.id
  nsg_id              = module.nsg.network_security_group_id
  be_pool_id          = module.lb.azurerm_lb_backend_address_pool_id
  node_size           = "Standard_B1ms"
  node_count          = 3
  password            = local.password
  username            = local.username
  data_disks          = {}
}

module "agent_pool" {
  providers           = { azurerm = azurerm }
  source              = "./module/k3s_pool"
  resource_group_name = module.foundations.rg.name
  environment         = local.env
  module              = "k3sa"
  subnet_id           = module.foundations.snet.id
  nsg_id              = module.nsg.network_security_group_id
  be_pool_id          = ""
  node_size           = "Standard_B1ms"
  node_count          = 2
  password            = local.password
  username            = local.username
  data_disks          = {}
}
