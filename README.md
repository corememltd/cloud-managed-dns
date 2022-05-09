Deploy and managed your authoritative DNS service with your cloud provider (currently only Azure) with support for [split-horizon DNS](https://en.wikipedia.org/wiki/Split-horizon_DNS) and on-premise recursive resolvers.

## Related Links

...

# Pre-flight

This project currently requires that you are using it on one of the following Operating Systems:

 * [Debian](https://debian.org/) 11 (bullseye) - tested
 * [Ubuntu](https://ubuntu.com/) 20.04 (focal)
 * [Microsoft WSL 2](https://docs.microsoft.com/en-us/windows/wsl/install-win10)

You will require pre-installed:

 * [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/)
     * have access to the Azure subscription you wish to deploy to
 * `make`
 * `unzip`

Start by logging into Azure via the CLI by running:

    az login

List the subscriptions you have access to with:

    az account list --output table

Pin the deployment to the [subscription of your choosing](https://docs.microsoft.com/en-us/azure/azure-portal/get-subscription-tenant-id) with (replacing `00000000-0000-0000-0000-000000000000` with your subscription ID):

    az account show --subscription 00000000-0000-0000-0000-000000000000 > account.json

The contents of this file should describe your selected subscription and the tenant it is part of.

# Deploy

## Authoritative DNS (Cloud)

    make deploy-authoritative DOMAIN=example.com LOCATION=uksouth SIZE=Standard_B1ls2

Where:

 * **`DOMAIN` (required):** domain you are hosting
 * **`LOCATION` (default: `uksouth`):** [region with availability zones](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones) nearest to your on-premise deployment
 * **`SIZE` (default: `Standard_B1ls2`):** [size of VM instance to use](https://docs.microsoft.com/azure/virtual-machines/sizes)
 * **`DRYRUN`:** if set to any value will run Terraform with `plan` instead of `apply`

## Recursive DNS (On-Premise)

...

# Usage and Testing

...
