variable "location" {
  type    = string
  default = "East US"
}

variable "client_secret" {
  type    = string
}

variable "tags" {
  type = map(string)
  default = {
    environment = "dev"
    costcenter  = "it"
  }
}
variable "teste" {
  type = map(string)
  default = {
    environment = "dev"
    costcenter  = "it"
  }
}
