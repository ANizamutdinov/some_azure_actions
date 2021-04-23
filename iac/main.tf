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
  username      = "sumgan"
  password      = "kuH85mLsWjCFLQdV5Vl"
}

module "foundations" {
  source = "./module/foundations"
  LOCATION = var.LOCATION
  env = local.env
  name_template = local.name_template
}

module "nsg" {
  source                = "Azure/network-security-group/azurerm"
  resource_group_name   = module.foundations.rg.name
  location              = module.foundations.rg.location
  security_group_name   = join("-", ["nsg", local.name_template])
  source_address_prefix = ["0.0.0.0/0"]
  predefined_rules = [
    {
      name     = "HTTP"
      priority = "300"
    },
    {
      name     = "SSH"
      priority = "310"
    }
  ]
}

module "lb" {
  source              = "Azure/loadbalancer/azurerm"
  resource_group_name = module.foundations.rg.name
  prefix              = local.name_template
  lb_sku             = "Standard"

  type                = "public"
  frontend_name       = join("-", ["lbfe", local.name_template])
  allocation_method   = "Static"
  pip_sku             = "Standard"

  lb_port = {
    http = ["80", "Tcp", "80"]
  }

  lb_probe = {
    http = ["Http", "8080", "/healthy"]
  }
}

module "docker_vms" {
  source              = "./module/vmss"
  resource_group_name = module.foundations.rg.name
  environment         = local.env
  module              = local.app
  subnet_id           = module.foundations.snet.id
  nsg_id              = module.nsg.network_security_group_id
  be_pool_id          = module.lb.azurerm_lb_backend_address_pool_id
  node_size           = "Standard_B1s"
  node_count          = 2
  password            = local.password
  username            = local.username
  data_disks          = { 1 = 32 }
}
