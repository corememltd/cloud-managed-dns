Deploy and managed your authoritative DNS service with your cloud provider (currently only Azure) with support for [split-horizon DNS](https://en.wikipedia.org/wiki/Split-horizon_DNS) and on-premise recursive resolvers.

This project is only of use to those looking to host their [private/internal zone](https://en.wikipedia.org/wiki/Split-horizon_DNS) in Azure and being able to query it on-premise. You should also be aware of the [per-request costs for using Azure DNS](https://azure.microsoft.com/en-in/pricing/details/dns/) before embarking on this project as well as the infrastructure costs of the deployment (roughly $30/month).

The expected DNS infrastructure topology this project supports is:

             On-Premise                                              Azure                                              Internet User
    +-------------------------+                 +----------------------------------------------+                 +-------------------------+
    |           +-----------+ |   example.com   |#############                ||               |   example.com   | +-----------+           |
    |           | Resolver  |----------\        |   Zone A   #                ||               |       /-----------| Resolver  |           |
    |           +-----|-----+ |        |        | +-------+  #                ||               |       |         | +-----------+           |
    +-----------------|-------+        +--------->|  DNS  |-----------v       ||               |       |         +-------------------------+
                      |                |        | | Proxy |  #   +---------+  ||  +---------+  |       |
       duckduckgo.com |                |        | +-------+  #   |  Azure  |  ||  |  Azure  |  |       |
                      |                |        |#############   | Private |  ||  |  Public |<---------/
                      v                |        |   Zone B   #   |   DNS   |  ||  |   DNS   |  |
    +------------------------------+   |        | +-------+  #   +---------+  ||  +---------+  |
    |    Root Name Servers and     |   \--------->|  DNS  |-----------^       ||               |
    |  Public Authorive Resolvers  |            | | Proxy |  #                ||               |
    |    (or upstream resolver)    |            | +-------+  #                ||               |
    +------------------------------+            |#############                ||               |
                                                +----------------------------------------------+

Out of scope to this project is the right hand side of the diagram encompassing the public DNS zone; here the focus is on the left side on-premise private DNS component.

Points to be aware of:

 * externally (ie. 'Internet User' on the right), *only* records in the public view will be returned
 * internally (ie. 'On-Premise' on the left), *only* records in the private view will be returned
     * records from the public view do not back fill into the private zone
         * this functionality is available in DNS Wingman (send enquires to info@coremem.com)
 * generally you should not put [special use IPs (RFC6890)](https://www.rfc-editor.org/rfc/rfc6890) into the public view
     * so not `192.168.0.0/16` or `fd00::/8`

There should be no need for you to interact with the Azure deployment other than to maintain your zones. The on-premise resolver may be anything of your choosing but this project does provide a suitable example Unbound configuration for you to use if you wish.

Though this project uses Hashicorp's Packer and Terraform tooling for deploying, there is no need for you to learn or understand these tools other than to install them.

## Related Links

 * [Azure](https://docs.microsoft.com/azure/)
    * [Azure DNS](https://docs.microsoft.com/azure/dns/dns-overview)
    * [Azure Private DNS](https://docs.microsoft.com/azure/dns/private-dns-overview)
        * [Split-Horizon functionality](https://docs.microsoft.com/en-us/azure/dns/private-dns-scenarios#scenario-split-horizon-functionality)
 * [Terraform](https://www.terraform.io/) ([Documentation](https://www.terraform.io/docs))
    * [Azure Tutorial](https://learn.hashicorp.com/collections/terraform/azure-get-started)
    * [azurerm](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
 * [Packer](https://www.packer.io/) ([Documentation](https://www.packer.io/docs))
 * [Unbound](https://nlnetlabs.nl/projects/unbound/about/) ([Documentation](https://unbound.docs.nlnetlabs.nl/en/latest/))
    * [`unbound.conf(5)`](https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html)

# Pre-flight

This project currently requires that your workstation is running one of the following Operating Systems:

 * [Debian](https://debian.org/) 12 (bookworm) - tested
 * [Ubuntu](https://ubuntu.com/) 22.04 (jammy)
 * [Microsoft WSL 2](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
 * macOS

You will require pre-installed:

 * [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/)
     * have (Contributor) access to the Azure subscription you wish to deploy to
 * `dig` ([Tutorial](https://phoenixnap.com/kb/linux-dig-command-examples)) - part of the Debian/Ubuntu `bind9-dnsutils` package
 * `git`
 * [Packer](https://www.packer.io/)
 * [Terraform](https://www.terraform.io/)

Check out this project and enter the project directory with:

    git clone https://github.com/corememltd/cloud-managed-dns.git
    cd cloud-managed-dns

Start by logging into Azure via the CLI by running:

    az login

List the subscriptions you have access to with:

    az account list --output table

Choose the [subscription you wish to deploy](https://docs.microsoft.com/en-us/azure/azure-portal/get-subscription-tenant-id) using the following command (replacing `00000000-0000-0000-0000-000000000000` with your subscription ID):

    az account show --subscription 00000000-0000-0000-0000-000000000000 > account.json

The contents of this file should describe your selected subscription and the tenant it is part of.

Using the example configuration file as a template:

    cp setup.hcl.example setup.hcl

Now edit `setup.hcl` to set at least the following to your needs:

 * **`group` (default: `cloud-managed-dns`):** [Azure Resource Group](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/manage-resource-groups-portal) to contain the DNS proxies
 * **`location`:** [region with at least two availability zones](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones)
     * it is recommended you deploy to the nearest location possible to your on-premise deployment
     * if you have several global sites, then you can deploy this service multiple times and they will act independently of one another
 * **`size` (default `Standard_B2ts_v2`):** instance size to use for Azure proxy DNS systems
     * suitable options are `Standard_B2ts_v2` (roughly $10/month) and `Standard_B2ats_v2` (roughly $10/month)
     * unscientific bench marking with `dnsperf` against a `Standard_B2ts_v2` instance provides of the order of 10krps
        * remember this is only for resolving your local private zone and your actual demands are going to be far lower still as the on-premise resolver will cache results
        * most deployments should expect the order of 100rps initially when restarting the on-premise resolver and then once the cache warms up dropping to less than 10rps (ie. 100x to 1000x less load!)
 * **`allowed_ips`:** this must encompass at least the (public) IPs of your on-premises DNS resolvers
     * if you are using [NAT](https://en.wikipedia.org/wiki/Network_address_translation) do *not* list your internal on-premise addresses as those will not be seen by Azure, you must use the public IP(s) of your NAT

To test that you have everything configured correctly, run the following:

    terraform init
    terraform validate
    
    packer init -var-file=setup.hcl setup.pkr.hcl
    packer validate -var-file=setup.hcl setup.pkr.hcl
    # https://github.com/hashicorp/packer-plugin-azure/issues/58
    az account set --subscription 00000000-0000-0000-0000-000000000000

## Safe Usage of Terraform

Terraform unfortunately needs to store information locally that describes the cloud deployment it manages, it does this by storing its state in a file named `terraform.tfstate`.

Only a single person at any moment may deploy (or decommission) the service and so when doing so you must pass around the latest version of the `terraform.tfstate` around your team; of course if you are a team of one you may ignore this to some extent but do *not* delete the file.

There are several ways that you may use in which to do this, and of course every team is different, but I would recommend either:

 * [recommended] store the [`.tfstate` file in Azure Storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli)
 * fork this project, edit `.gitignore` to no longer ignore `terraform.tfstate` by adding `!terraform.tfstate` *after* the existing `terraform.tfstate*` entry, commit the state to the project
 * store the file on some networking resource (eg. Microsoft Windows/Samba share, NFS, SFTP, Dropbox, ...)

# Deploy

The deployment of the service has several parts that are tackled in the following order:

 1. Azure Private DNS zones
 1. Azure hosted DNS proxies
 1. On-premise resolvers

Throughout the instructions we will assume your environment has the following values:

 * the Azure Subscription you are deploying into has the value `00000000-0000-0000-0000-000000000000`
 * the Azure location you wish to deploy to is `uksouth`
 * the Azure Resource Group containing your zones is called `DNS`
 * the Azure Resource Group containing the DNS proxies is called `cloud-managed-dns` (the default)
 * your private zone is `example.com`

The instructions describing using the CLI for configuring the zone, but if you prefer you may use the web based portal instead.

## Azure Private DNS Zones

### Creating the Zone

If you have not already, you need to create a resource group to hold your private zones:

    az group create --subscription 00000000-0000-0000-0000-000000000000 --location uksouth --resource-group DNS

Now we create the private DNS zone(s) themselves using::

    az network private-dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name example.com

**N.B.** run this command for each private zone you wish to host in Azure

It is recommended you also host the reverse zones too. A simply and fast way to get the special use IP ranges added is to run:

    az network private-dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name d.f.ip6.arpa
    az network private-dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name 10.in-addr.arpa
    az network private-dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name 168.192.in-addr.arpa
    seq 16 31 | xargs -I{} -t az network private-dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name {}.172.in-addr.arpa

### Populating the Zone

You now need to populate your Azure DNS zone(s) with records. You can do this manually via the web portal or CLI, but if your existing DNS service supports exporting a zone file (or AXFR) then it is far faster and more reliable to use the Azure zone importing functionality built into the CLI.

To use this you will need a copy of your zone as a traditional BIND zone file, your existing authoritative DNS server (check the vendor documentation!) should let you generate one via an AXFR query using something like:

    dig AXFR @192.0.2.1 example.com | tee example.com.axfr

**N.B.** you may need to grant yourself permission on the server to be able to do a zone transfer, but this process is out of scope to this document

Once you have a zone file, you can import it using (replacing the `-n` and `-f` parameters) depending on the view you are importing:

    az network private-dns zone import --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --name example.com --file-name example.com.axfr

## Azure Hosted DNS Proxies

First we build the virtual machine image by running the following:

    COMMIT=$(git describe --always --dirty)
    terraform apply ${COMMIT:+-var commit=$COMMIT} -var-file=setup.hcl -auto-approve -target azurerm_resource_group.main
    packer build ${COMMIT:+-var commit=$COMMIT} -var-file=setup.hcl setup.pkr.hcl

**N.B.** it is safe here to ignore the 'target' related warnings when running `terraform`

After some time (typically five to ten minutes) it should complete building the OS image to be used by the DNS proxies.

Now we deploy the entire infrastructure using:

    terraform apply ${COMMIT:+--var commit=$COMMIT} -var-file=setup.hcl -auto-approve -target random_shuffle.zones
    terraform apply ${COMMIT:+--var commit=$COMMIT} -var-file=setup.hcl -auto-approve

**N.B.** it is safe here to ignore the 'target' related warnings when running `terraform`

When the process completes (typically five to ten minutes) you will be [returned output](https://www.terraform.io/language/values/outputs) that resembles:

    dns-proxy-0-ipv4 = "192.0.2.4"
    dns-proxy-0-ipv6 = "2001:db8:100:8::43"
    dns-proxy-1-ipv4 = "192.0.2.79"
    dns-proxy-1-ipv6 = "2001:db8:100:8::2e"

These are the IP addresses of the Azure hosted DNS proxies.

To test everything is working, run on a system that has a listed IP in `setup.hcl`, you should be able to run the following against the IPs of the DNS proxies and see something like the following:

    $ dig CH TXT version.server @192.0.2.4
    "unbound 1.17.1"

### Access to the Private DNS Zones

For the DNS proxies to be able to see your Azure Private DNS zones, you need to create [virtual network link(s)](https://learn.microsoft.com/en-us/azure/dns/private-dns-virtual-network-links) to link them to each of the private DNS zones (including the reverse ones).

This is done by running:

    ID=$(az network vnet show --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --name network --output tsv --query id)
    
    az network private-dns link vnet create --no-wait --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name cloud-managed-dns --virtual-network $ID --registration-enabled False --zone-name example.com
    az network private-dns link vnet create --no-wait --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name cloud-managed-dns --virtual-network $ID --registration-enabled False --zone-name d.f.ip6.arpa
    az network private-dns link vnet create --no-wait ...

Once you have imported the records, you should be able to test them using `dig` as follows:

    $ dig @192.0.2.4 +noall +comments +answer SOA example.com
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 2616
    ;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; ANSWER SECTION:
    example.com.		65	IN	SOA	azureprivatedns.net. azureprivatedns-host.microsoft.com. 1 3600 300 2419200 10

Initially, the status in the comment section will be set to `REFUSED` (as it will for all unlinked zones) but after a minute or two you should start seeing status being set to `NOERROR` and the expected result coming through.

If this does not work:

  * verify your [external IP for the workstation](https://developers.cloudflare.com/1.1.1.1/) is in the network security group (original set by `allowed_ips` in `setup.hcl`) using:

        dig CH TXT whoami.cloudflare @1.1.1.1
        dig CH TXT whoami.cloudflare @2606:4700:4700::1111

  * check that a local firewall is not blocking you directly querying non-local DNS servers
  * check there were no deployment errors, if there were, retry that process until there are no errors

## On-Premise Resolvers

This part walks you though configuring Unbound, but the configuration here can be applied to any vendor DNS resolver software of your choosing.

To build a suitable on-premise Unbound resolver, start by creating a VM using the following:

 * running Debian 'bookworm' 12
    * if you prefer a Ubuntu LTS release instead, then do use that instead
 * 1GiB RAM
 * two (2) vCPU cores
 * 30GiB of disk space

It is strongly recommended you also:

 * use `sudo` and add your regular users to the `sudo` group (never log into the system directly as `root`)
 * edit `/etc/ssh/sshd_config` setting `PermitRootLogin no` and `PasswordAuthentication no`
 * use `/etc/securetty` only allows the console and serial port, which you can configure by running:

       cat <<'EOF' | sudo tee /etc/securetty >/dev/null
       console
       ttyS0
       EOF

   Now add to the top of `/etc/pam.d/login`:

       auth [success=1 default=ignore] pam_securetty.so

   With this inplace you may *optionally* wish to remove the password from the `root` account using `passwd -d root` but your own preferences may dictate otherwise.

Once built and ready, you need to install `unbound` using:

   sudo apt install unbound

### Zone Delegations (`NS` records)

Azure Private DNS [does not support zone delegations](https://learn.microsoft.com/en-us/azure/dns/private-dns-privatednszone#restrictions) so you need to configure unbound to do this on your behalf.

**N.B.** it is recommended you do this on your on-premise recursive resolvers but you may decide for local reasons you want to do it on the DNS proxies

As an example of how to do this, you may wish to add the following to `/etc/unbound/unbound.conf.d/delegations.conf`:

    # Azure Private DNS does not support delegation (ie. NS records)
    # https://learn.microsoft.com/en-us/azure/dns/private-dns-privatednszone#restrictions
    # https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#unbound-conf-stub
    server:
        domain-insecure: "subdomain.example.com."
    
    # dig NS subdomain.example.com @ns2.subdomain.example.com.
    stub-zone:
        name: subdomain.example.com
        stub-prime: yes
        stub-addr: 192.0.2.100     # ns1.subdomain.example.com.
        stub-addr: 2001:db8::aaaa  # ns1.subdomain.example.com.
        stub-addr: 192.0.2.101     # ns2.subdomain.example.com.
        stub-addr: 2001:db8::bbbb  # ns2.subdomain.example.com.

# Troubleshooting

## Accessing the DNS Proxies

To initially access the proxy, you use the [serial port](https://learn.microsoft.com/en-us/troubleshoot/azure/virtual-machines/serial-console-overview) which requires a local extension:

    az extension add --name serial-console --upgrade

To enable the serial console on the VMs, run the following:

    az vm boot-diagnostics enable --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --name dns-proxy-0
    az vm boot-diagnostics enable --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --name dns-proxy-1

Now to access the serial port (of `dns-proxy-0`) run:

    az serial-console connect --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --name dns-proxy-0

Log in as `root`, no password is required; do not freak out as SSH is configured with `PermitRootLogin no` and `PasswordAuthentication no` whilst `/etc/securetty` only allows the console and serial port.

Using the serial port is somewhat slow (and glitchy if you are unfamiliar with the process) so using this access you should arrange SSH access for yourself:

 1. create yourself a user:

        useradd -U -G sudo -m -s /bin/bash bob

 1. set a password on the account for the purposes of using `sudo`:

        passwd bob

 1. add your SSH key:

        sudo -s -u bob
        mkdir ~/.ssh
        vim ~/.ssh/authorized_keys

 1. update the firewall to allow access to the VMs from your IP address:

        az network nsg rule create --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --priority 2000 --nsg-name nsg --name ssh-0 --source-address-prefixes 192.0.2.0/24 --protocol Tcp --destination-port-ranges 22 --access Allow

    **N.B.** run this command multiple times if you need additional IP ranges, but remember to update `name` and increment `priority`

You should now be able to SSH into the system either directly by IP or using:

    az ssh vm --subscription 00000000-0000-0000-0000-000000000000 --resource-group cloud-managed-dns --name dns-proxy-0 --local-user bob

Remember to log out of the serial console once you have finished (typing `exit`, `logout` or `Ctrl-D` until you see the login prompt) and then disconnect by pressing `Ctrl-]` followed by `q`.

## DNS Resolution From the Proxies

If you have SSHed into one of the the proxy resolvers, when using `dig` you instead would use:

    dig @127.0.0.1 SOA example.com

To bypass the DNS proxy and speak directly to Azure's DNS service, you should point your request at [`168.63.129.16`]https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16() instead use:

    dig @168.63.129.16 SOA example.com
