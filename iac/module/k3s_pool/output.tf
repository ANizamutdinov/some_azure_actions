output "fqdns" {
  value = [azurerm_public_ip.k3s.*.fqdn]
}