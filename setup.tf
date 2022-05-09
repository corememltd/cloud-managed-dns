variable "vendor" {
  default = "coremem"
}
variable "project" {
  default = "cloud-managed-dns"
}
variable "commit" {
  default = "dev"
}

variable "location" {
  default = "uksouth"
}
variable "domain" {
  default = "example.invalid"
}
variable "size" {
  default = "Standard_B1ls"
}

locals {
  prefix = "${var.vendor}-${var.project}"
  account = jsondecode(file("account.json"))
  resource_group_name = local.prefix
  zones = sort(jsondecode(module.zones.stdout))
}

terraform {
  required_version = ">= 1.1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.5.0"
    }
  }
}

module "zones" {
  source = "Invicton-Labs/shell-resource/external"

  command_unix = "az vm list-skus --location ${var.location} --resource-type virtualMachines --size ${var.size} --query '[0].locationInfo[0].zones'"
}

resource "random_shuffle" "zones" {
  input        = sort(jsondecode(module.zones.stdout))

  result_count = 2
}

provider "azurerm" {
  tenant_id = local.account.tenantId
  subscription_id = local.account.id

  features {
  }
}

resource "azurerm_resource_group" "rg" {
  name     = "${local.prefix}-${local.resource_group_name}"
  location = var.location
  tags     = {
    Vendor  = "coreMem Limited"
    Project = "Cloud Managed DNS"
    URI     = "https://coremem.com/"
    Email   = "info@coremem.com"
  }
}

resource "azurerm_dns_zone" "public" {
  name                = "${local.prefix}-${var.domain}"
  resource_group_name = azurerm_resource_group.rg.name

  # force the user to have to manually delete this as the
  # APEX NS records on the zone are randomly chosen by
  # Azure on creation which is unlikely to match the NS
  # records configured with the domain name registrar
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_private_dns_zone" "private" {
  name                = "${local.prefix}-${var.domain}"
  resource_group_name = azurerm_resource_group.rg.name
}

output "zones" {
  value = random_shuffle.zones.result
}

output "nameservers" {
  value = azurerm_dns_zone.public.name_servers
}
