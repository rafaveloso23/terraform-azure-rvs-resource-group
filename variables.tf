# variable "resource_group_name" {
#   type    = string
#   default = "rg-name-region"
# }

variable "location" {
  type    = string
  default = "East US"
}

variable "tags" {
  type = map(string)
  default = {
    environment = "dev"
    costcenter  = "it"
  }
}
