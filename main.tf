resource "azurerm_resource_group" "rg" {
  name     = "rg-teste"
  location = var.location
  tags     = var.tags
}##