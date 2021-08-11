output "lbfqdn" {
  value = module.lb.azurerm_public_ip_fqdn
}
output "master_fqdns" {
  value = module.master_pool.fqdns
}
output "agent_fqdns" {
  value = module.agent_pool.fqdns
}
