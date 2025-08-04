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


variable "azurerm_key_vault_access_policy_object_id" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}

variable "azurerm_key_vault_access_policy_name" {
  type    = string
  default = "00000000-0000-0000-0000-000000000000"
}
