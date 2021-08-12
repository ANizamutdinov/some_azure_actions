output "endpoint_kctl" {
  value = module.lb.azurerm_public_ip_fqdn
}
output "endpoint_wload" {
  value = module.lb_wload.azurerm_public_ip_fqdn
}
output "fqdns_master" {
  value = module.master_pool.fqdns
}
output "fqdns_agent" {
  value = module.agent_pool.fqdns
}
