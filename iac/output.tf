output "http-endpoint" {
  value = join(["http://", module.lb.azurerm_public_ip_address])
}