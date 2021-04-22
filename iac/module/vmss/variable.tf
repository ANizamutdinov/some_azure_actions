variable "resource_group_name" {}
variable "environment" {}
variable "module" {}
variable "node_size" {}
variable "subnet_id" {}
variable "nsg_id" {}
variable "username" {}
variable "password" {}
variable "tags" {
  default = {}
}
variable "data_disk_type" {
  default = ""
}
variable "data_disks" {
  default = {}
}
variable "be_pool_id" {
  default = ""
}
variable "node_image" {
  default = ""
}
variable "node_count" {
  default = 1
}