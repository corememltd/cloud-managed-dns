variable "vendor" {
  type = string
  nullable = false
  default = "coremem"
}
variable "project" {
  type = string
  nullable = false
  default = "cloud-managed-dns"
}
variable "commit" {
  type = string
  nullable = false
  default = "dev"
}

variable "domain" {
  type = string
  nullable = false
  description = "The domain you are hosting, such as 'example.invalid'"
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
  default = "Standard_B1ls"
  description = "Specify the size of VM instance to use (https://docs.microsoft.com/azure/virtual-machines/sizes)"
}
variable "allowed_ips" {
  type = list(string)
  nullable = false
  description = "List the external IPv4 and IPv6 addresses or CIDR prefixes that will be allowed to query the private zone (this must include the public IP's of your on-premises DNS resolvers)"
}

locals {
  prefix = "${var.vendor}-${var.project}"
  account = jsondecode(file("account.json"))
  zones = sort(random_shuffle.zones.result)
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
  name     = "${local.prefix}"
  location = var.location
  tags     = {
    Vendor  = "coreMem Limited"
    Project = "Cloud Managed DNS"
    Commit  = var.commit
    URI     = "https://coremem.com/"
    Email   = "info@coremem.com"
  }
}

resource "azurerm_dns_zone" "main" {
  name                = "${local.prefix}-${var.domain}"
  resource_group_name = azurerm_resource_group.main.name

  # force the user to have to manually delete this as the
  # APEX NS records on the zone are randomly chosen by
  # Azure on creation which is unlikely to match the NS
  # records configured with the domain name registrar
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_private_dns_zone" "main" {
  name                = "${local.prefix}-${var.domain}"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_virtual_network" "main" {
  name                = "${local.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# https://github.com/hashicorp/terraform-provider-azurerm/blob/main/examples/virtual-machines/linux/public-ip/
resource "azurerm_subnet" "main" {
  count = length(local.zones)

  name                 = "${local.prefix}-subnet-${count.index}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.${count.index}.0/24"]
}

resource "azurerm_public_ip" "ip" {
  count = length(local.zones)

  # use the index as a suffix so we retain it across redeploys
  name                = "${local.prefix}-ip-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Dynamic"

  # force the user to have to manually delete this as the
  # we want to recycle them where possible to avoid having
  # to reconfigure the on-premises systems
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_network_interface" "main" {
  count = length(local.zones)

  name                = "${local.prefix}-nic-${count.index}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.main[count.index].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip[count.index].id
  }
}

resource "azurerm_network_security_group" "main" {
  name                = "${local.prefix}-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_network_security_rule" "dns-udp" {
  count = length(var.allowed_ips)

  name                        = "${local.prefix}-nsr-dns-udp-${count.index}"
  priority                    = (1000 + 2 * count.index)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = "*"
  destination_port_range      = "53"
  source_address_prefix       = var.allowed_ips[count.index]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = "${local.prefix}-nsg"
}

resource "azurerm_network_security_rule" "dns-tcp" {
  count = length(var.allowed_ips)

  name                        = "${local.prefix}-nsr-dns-tcp-${count.index}"
  priority                    = (1001 + 2 * count.index)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "53"
  source_address_prefix       = var.allowed_ips[count.index]
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = "${local.prefix}-nsg"
}

resource "azurerm_network_interface_security_group_association" "main" {
  count = length(local.zones)

  network_interface_id      = azurerm_network_interface.main[count.index].id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_linux_virtual_machine" "main" {
  count = length(local.zones)

  name                            = "${local.prefix}-vm-${count.index}"
  location                        = azurerm_resource_group.main.location
  resource_group_name             = azurerm_resource_group.main.name
  zone                            = local.zones[count.index]
  size                            = var.size
  custom_data                     = base64encode(var.domain)
  admin_username                  = "root"
  disable_password_authentication = true
  network_interface_ids = [
    azurerm_network_interface.main[count.index].id,
  ]

  admin_ssh_key {
    username = "root"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22.04-LTS"
    version   = "latest"
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
}

output "nameservers" {
  value = azurerm_dns_zone.main.name_servers
}
