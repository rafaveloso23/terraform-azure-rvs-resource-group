variable "azurerm_resource_group_name" {
  type    = string
  default = "rgtest4te45"
}

variable "tags" {
  type = map(string)
  default = {
    environment = "dev"
    costcenter  = "it"
  }
}

variable "azurerm_resource_group_location" {
  type    = string
  default = "East US"
}


variable "azurerm_key_vault_name" {
  type    = string
  default = "myKeyVault"
}
