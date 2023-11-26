variable "group" {
  type = string
  nullable = false
  default = "cloud-managed-dns"
}
variable "commit" {
  type = string
  nullable = false
  default = "dev"
}

variable "location" {
  type = string
  nullable = false
  default = "uksouth"
  description = "region with availability zones (https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones) nearest to your on-premise deployment"
}
variable "size" {
  type = string
  nullable = false
  default = "Standard_B2ts_v2"
  description = "Specify the size of VM instance to use (https://docs.microsoft.com/azure/virtual-machines/sizes)"
}
variable "allowed_ips" {
  type = list(string)
  description = "List the external IPv4 and IPv6 addresses or CIDR prefixes that will be allowed to query the private zone (this must include the public IP's of your on-premises DNS resolvers)"
}

locals {
  account = jsondecode(file("account.json"))
  zones = sort(random_shuffle.zones.result)

  # Azure will not let us create a VM without admin credentials
  custom_data = <<CUSTOM_DATA
#!/bin/sh
userdel -f -r packer
userdel -f -r notroot
CUSTOM_DATA
}

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

module "zones" {
  source = "Invicton-Labs/shell-resource/external"

  command_unix = "az vm list-skus --location ${var.location} --resource-type virtualMachines --size ${var.size} --query '[0].locationInfo[0].zones'"
}

resource "random_shuffle" "zones" {
  input        = jsondecode(module.zones.stdout)

  result_count = 2
}

provider "azurerm" {
  tenant_id = local.account.tenantId
  subscription_id = local.account.id

  features {
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.group
  location = var.location
  tags     = {
    Vendor  = "coreMem Limited"
    Project = "Cloud Managed DNS"
    Commit  = var.commit
    URI     = "https://coremem.com/"
    Email   = "info@coremem.com"
  }
}

resource "azurerm_virtual_network" "main" {
  name                = "network"
  address_space       = [ "10.0.0.0/16", "fd00:db8:deca:da00::/56" ]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# https://github.com/hashicorp/terraform-provider-azurerm/blob/main/examples/virtual-machines/linux/public-ip/
resource "azurerm_subnet" "main" {
  count = length(local.zones)

  name                 = "subnet-${count.index}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [ "10.0.${count.index}.0/24", format("fd00:db8:deca:da%02d::/64", count.index) ]
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_rule" "dns-udp" {
  count = length(var.allowed_ips)

  name                        = "nsr-dns-udp-${count.index}"
  priority                    = (1000 + 2 * count.index)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "53"
  source_address_prefix       = var.allowed_ips[count.index]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_network_security_rule" "dns-tcp" {
  count = length(var.allowed_ips)

  name                        = "nsr-dns-tcp-${count.index}"
  priority                    = (1001 + 2 * count.index)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "53"
  source_address_prefix       = var.allowed_ips[count.index]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.main.name
}

resource "azurerm_public_ip" "ipv6" {
  count = length(local.zones)

  # use the index as a suffix so we retain it across redeploys
  name                = "ipv6-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  # use the full list of zones
  zones               = sort(jsondecode(module.zones.stdout))

  ip_version          = "IPv6"

  # force the user to have to manually delete this as the
  # we want to recycle them where possible to avoid having
  # to reconfigure the on-premises systems
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_public_ip" "ipv4" {
  count = length(local.zones)

  # use the index as a suffix so we retain it across redeploys
  name                = "ipv4-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  # use the full list of zones
  zones               = sort(jsondecode(module.zones.stdout))

  ip_version          = "IPv4"

  # force the user to have to manually delete this as the
  # we want to recycle them where possible to avoid having
  # to reconfigure the on-premises systems
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_network_interface" "main" {
  count = length(local.zones)

  name                          = "nic-${count.index}"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "nic-ipv4-${count.index}"
    primary                       = true
    private_ip_address_version    = "IPv4"
    subnet_id                     = azurerm_subnet.main[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ipv4[count.index].id
  }

  ip_configuration {
    name                          = "nic-ipv6-${count.index}"
    private_ip_address_version    = "IPv6"
    subnet_id                     = azurerm_subnet.main[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ipv6[count.index].id
  }
}

resource "azurerm_network_interface_security_group_association" "main" {
  count = length(local.zones)

  network_interface_id      = azurerm_network_interface.main[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_linux_virtual_machine" "main" {
  count = length(local.zones)

  name                            = "dns-proxy-${count.index}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  zone                            = local.zones[count.index]
  size                            = var.size

  network_interface_ids = [
    azurerm_network_interface.main[count.index].id,
  ]

  source_image_id = "/subscriptions/${local.account.id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.Compute/images/dns-proxy"

  os_disk {
    disk_size_gb         = 10
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  # do not freak out, we burn this immediately via custom_data
  disable_password_authentication = false
  admin_username = "notroot"
  admin_password = "notValid12$"
  custom_data = base64encode(local.custom_data)
}

output "dns-proxy-0-ipv6" {
  value = azurerm_public_ip.ipv6[0].ip_address
}
output "dns-proxy-0-ipv4" {
  value = azurerm_public_ip.ipv4[0].ip_address
}
output "dns-proxy-1-ipv6" {
  value = azurerm_public_ip.ipv6[1].ip_address
}
output "dns-proxy-1-ipv4" {
  value = azurerm_public_ip.ipv4[1].ip_address
}
