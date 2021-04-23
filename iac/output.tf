output "http-endpoint" {
  value = format("http://%s", module.lb.azurerm_public_ip_address)
}