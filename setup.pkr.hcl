variable "group" {
  type = string
  default = "cloud-managed-dns"
}
variable "commit" {
  type = string
  default = "dev"
}

variable "location" {
  type = string
  default = "uksouth"
  description = "region with availability zones (https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones) nearest to your on-premise deployment"
}
variable "size" {
  type = string
  default = "Standard_B2ts_v2"
  description = "Specify the size of VM instance to use (https://docs.microsoft.com/azure/virtual-machines/sizes)"
}
variable "allowed_ips" {
  type = list(string)
  description = "List the external IPv4 and IPv6 addresses or CIDR prefixes that will be allowed to query the private zone (this must include the public IP's of your on-premises DNS resolvers)"
}

locals {
  account = jsondecode(file("account.json"))
}

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2"
    }
  }
}

source "azure-arm" "main" {
  use_azure_cli_auth = true

  tenant_id = local.account.tenantId
  subscription_id = local.account.id

  location = var.location

  azure_tags     = {
    Vendor  = "coreMem Limited"
    Project = "Cloud Managed DNS"
    Commit  = var.commit
    URI     = "https://coremem.com/"
    Email   = "info@coremem.com"
  }

  vm_size = var.size

  os_type = "Linux"

  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  image_version   = "latest"

  managed_image_resource_group_name = var.group
  managed_image_zone_resilient = true
  managed_image_name = "dns-proxy"
}

build {
  sources = [ "source.azure-arm.main" ]

  # https://www.packer.io/docs/other/debugging.html#issues-installing-ubuntu-packages
  provisioner "shell" {
    inline = [
      "echo Waiting for cloud-init to finish",
      "cloud-init status --wait"
    ]
  }

  provisioner "shell-local" {
    inline_shebang = "/bin/sh -eux"
    inline = [
      "git bundle create bundle.git HEAD"
    ]
  }

  provisioner "file" {
    generated = true
    source = "bundle.git"
    destination = "/tmp/bundle.git"
  }

  provisioner "shell-local" {
    inline_shebang = "/bin/sh -eux"
    inline = [
      "rm bundle.git"
    ]
  }

  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E sh -x '{{ .Path }}'"
    script = "setup.sh"
  }

  # https://docs.microsoft.com/en-us/azure/virtual-machines/generalize
  provisioner "shell" {
    execute_command = "{{ .Vars }} sudo -E sh -eux"
    inline = [
      "find /var/log/ -type f -delete",
      "find \"$(getent passwd root | cut -d: -f6)/.ssh\" -type f -print0 2>&- | xargs -r -0 shred -u",
      "rm -rf \"$(getent passwd root | cut -d: -f6)/.ssh\"",
      "waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
  }
}
