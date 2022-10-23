variable "vendor" {
  type = string
  default = "coremem"
}
variable "project" {
  type = string
  default = "cloud-managed-dns"
}
variable "commit" {
  type = string
  default = "dev"
}

variable "domains" {
  type = list(string)
  description = "The domains you are hosting, such as 'example.invalid'"
}
variable "location" {
  type = string
  default = "uksouth"
  description = "region with availability zones (https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones) nearest to your on-premise deployment"
}
variable "size" {
  type = string
  default = "Standard_B1ls"
  description = "Specify the size of VM instance to use (https://docs.microsoft.com/azure/virtual-machines/sizes)"
}
variable "allowed_ips" {
  type = list(string)
  description = "List the external IPv4 and IPv6 addresses or CIDR prefixes that will be allowed to query the private zone (this must include the public IP's of your on-premises DNS resolvers)"
}

locals {
  account = jsondecode(file("account.json"))
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

  managed_image_resource_group_name = "${var.vendor}-${var.project}"
  managed_image_zone_resilient = true
  managed_image_name = "dns-proxy-resolver"
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
      "git bundle create ${var.vendor}-${var.project}.git HEAD"
    ]
  }

  provisioner "file" {
    generated = true
    source = "${var.vendor}-${var.project}.git"
    destination = "/tmp/${var.vendor}-${var.project}.git"
  }

  provisioner "shell-local" {
    inline_shebang = "/bin/sh -eux"
    inline = [
      "rm ${var.vendor}-${var.project}.git"
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
