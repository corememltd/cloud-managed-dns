Deploy and managed your authoritative DNS service with your cloud provider (currently only Azure) with support for [split-horizon DNS](https://en.wikipedia.org/wiki/Split-horizon_DNS) and on-premise recursive resolvers.

This project is only of use to those looking to host their [private/internal zone](https://en.wikipedia.org/wiki/Split-horizon_DNS) in Azure and being able to query it on-premise. You should also be aware of the [per-request costs for using Azure DNS](https://azure.microsoft.com/en-in/pricing/details/dns/) before embarking on this project as well as the infrastructure costs of the deployment (~$50/month).

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

Out of scope to this project is the right hand side of the diagram encompassing the public DNS zone; here the focus is on the left side on-premise private DNS componment.

There should be no need for you to interact with the Azure deployment other than to maintain your zones. The on-premise resolver may be anything of your choosing but this project does provide a suitable example Unbound configuration for you to use if you wish.

Though this project uses Hashicorp's Packer and Terraform tooling for deploying, there is no need for you to learn or understand these tools other than to install them.
A
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
     * suitable options are `Standard_B2ts_v2` (~$10/month) and `Standard_B2ats_v2` (~$10/month)
     * unscientific benchmarking with `dnsperf` against a `Standard_B2ts_v2` benchmarks above 10krps
        * remember this is only for resolving your local private zone and your actual demands are going to be far lower still as the on-premise resolver will cache results
        * most deployments should expect the order of 100rps initially when restaring the on-premise resolver and then once the cache warms up dropping to less than 10rps
 * **`allowed_ips`:** this must encompass at least the (public) IPs of your on-premises DNS resolvers
     * if you are using [NAT](https://en.wikipedia.org/wiki/Network_address_translation) do *not* list your internal on-premise addresses as those will not be seen by Azure, you must use the public IP(s) of your NAT

To test that you have everything configured correctly, run the following:

    terraform init
    terraform validate
    
    packer init -var-file=setup.hcl setup.pkr.hcl
    packer validate -var-file=setup.hcl setup.pkr.hcl
    # https://github.com/hashicorp/packer-plugin-azure/issues/58
    az account set --subscription 00000000-0000-0000-0000-000000000000

# Deploy

The deployment of the service has several parts that are tackled in the following order:

 1. Azure Private DNS service and the zones
 1. Azure hosted DNS proxies
 1. On-premise resolvers

Thoughout the instructions we will assume your environment has the following values:

 * the Azure Subscription you are deploying into has the value `00000000-0000-0000-0000-000000000000`
 * the Azure location you wish to deploy to is `uksouth`
 * the Azure Resource Group containing your zones is called `DNS`
 * the Azure Resource Group containing the DNS proxies is called `cloud-managed-dns` (the default)
 * your private zone is `example.com`

The instructions describing using the CLI for configuring the zone, but if you prefer you may use the web based portal instead.

## Azure Private DNS service

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

####

https://learn.microsoft.com/en-us/azure/dns/private-dns-virtual-network-links

Once you have created the private zone(s), you need to create virtual network link(s) from the proxy resolver network back to each of the private DNS zones (including the reverse ones) you have created:

    az network private-dns link vnet create --no-wait --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name cloud-managed-dns --zone-name example.com
    az network private-dns link vnet create --no-wait --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name cloud-managed-dns --zone-name d.f.ip6.arpa
    az network private-dns link vnet create --no-wait ...


Once you have imported the records, you should be able to test them as detailed below.




Whilst following the below deploy process, early into it you may see it stall with something like the following message:

    ==> azure-arm.main: Microsoft Azure: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ABCD12345 to authenticate.

You should follow the instructions shown there to authorise the CLI tooling to perform tasks using your user credentials.

**N.B.** annoyingly you will need to do this twice, one immediately after the other but once done you should be able to walk away and get a coffee

**N.B.** if you see an error stating `Cannot locate the managed image resource group ...` then try deleting `~/.azure/packer` and retrying

**N.B.** ignore any `Duplicate required provider` warnings in regards to the `random_uuid` module, it is a bug in someone else's code we cannot work around and fortunately is harmless

## Authoritative DNS (Cloud)

Initially we need to build an image for our DNS proxy resolver to run in Azure, this is done with:

    make build-proxy

Once the image has been cooked, you can now deploy the infrastructure for this with:

    make deploy

**N.B.** if you append `DRYRUN=1` to the end, the process will run Terraform in `plan` mode instead of `apply` so no changes will be applied

When the process completes (first run will take at least ten minutes), you will be [returned output](https://www.terraform.io/language/values/outputs) that resembles the *example* below:

    proxy-ipv6 = [
      "2001:db8:100:8::43",
      "2001:db8:100:8::2e"
    ]
    proxy-ipv4 = [
      "192.0.2.4",
      "192.0.2.79"
    ]

Where:

 * **`proxy-ipv6` and `proxy-ipv4`:** IPv6 and IPv4 addresses of the DNS proxy forwarders
     * first IPv4 and first IPv6 address listed is assigned to the first proxy resolver, the second set to the second proxy resolver
     * these IPs are used by your on-premises resolvers to gain access to the private view of your zone
     * you should be able to SSH into these systems using:

## Security

You should not need to ever log into the proxy resolvers but as they are configured with a temporary SSH public key (`id_rsa` and `id_rsa.pub` would have been automatically created for you at the top of the project directory) you should perform the following steps on each system:

 1. SSH into the server (from within the project directory) with:

        ssh -i id_rsa ubuntu@192.0.2.1

 1. create user accounts for yourself and anyone else who will be administrating the system

 1. make sure you can log into the system (and gain `root` via `sudo -s`) using at least one of those accounts

 1. delete the `ubuntu` account by running on the system

        sudo userdel -r ubuntu

**N.B.** you will need to redo this each time you update the domains list in `setup.hcl` as the VMs are rebuilt

## Importing

## Recursive DNS (On-Premises)

Each on-premise environment is different, and forcing the administrator to use a given orchestration tool will not fly.

Instead provided is a shell script ([`setup.resolver.sh`](./setup.resolver.sh)) that you should copy to a fresh recent Debian or Ubuntu based system and run there as `root` the following:

    export DOMAINS=example.com,example.org
    export NSS=192.0.2.1,192.0.2.241,2001:db8::1234,2001:db8::9876
    sh setup.resolver.sh

**N.B.** `DOMAINS` is a list of the domains comma separated you added to `setup.hcl` and `NSS` is the list of all the IPs returned comma separated for the Azure hosted DNS proxies

The configuration installed will serve stale records for up to 24 hours (`/etc/unbound/unbound.conf.d/stale.conf`) in case there is a problem with reaching the upstream Azure hosted proxies.

You may need to edit `/etc/unbound/unbound.conf.d/listen.conf` to add additional source IP ranges that can query your resolver.

### Zone Delegations (`NS` records)

Azure Private DNS [does not support zone delegations](https://learn.microsoft.com/en-us/azure/dns/private-dns-privatednszone#restrictions) so you need to configure unbound to do this on your behalf.

**N.B.** it is recommended you do this on your on-premise recursive resolvers but you may decide for local reasons you want to do it on the proxy DNS systems

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

# Usage and Testing

This section will walk you through testing your service before putting it into production.

We will assume your DNS zones (private and public) will be placed into the resource group 'DNS'.

Points to be aware of:

 * externally, *only* records in the public view will be returned
 * internally, *only* records in the private view will be returned
     * records from the public view do not back fill
         * this functionality is available in DNS Wingman (send enquires to info@coremem.com)
 * generally you should not put [special use IPs (RFC6890)](https://www.rfc-editor.org/rfc/rfc6890) into the public view
     * so not `192.168.0.0/16` or `fd00::/8`

## Public

You need to create the public DNS zones manually using something like:

    az network dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name example.com
    az network dns zone create ...

You should also do the same for the reverse zones for any IP space allocated to you:

    az network dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name 8.b.d.0.1.0.0.2.ip6.arpa
    az network dns zone create ...

Once you have populated your public zone, then you should be able to see your expected result for it with:

    dig @nsA-0Y.azure-dns.com server.example.com

Where `nsA-0Y.azure-dns.com` is one of the entries from the `nameservers` output produced when you were creating that zone.

## Private

You need to create the DNS zones yourself manually using something like:

    az network private-dns zone create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name example.com
    az network private-dns zone create ...

You should also do the same for the reverse zones. A quick way to get the special use ones configured is to run:

    az network private-dns zone create --only-show-errors --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name d.f.ip6.arpa
    az network private-dns zone create --only-show-errors --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name 10.in-addr.arpa
    az network private-dns zone create --only-show-errors --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name 168.192.in-addr.arpa
    seq 16 31 | xargs -I{} -t az network private-dns zone create --only-show-errors --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name {}.172.in-addr.arpa

Once you have created the private zones, you need to create virtual network links from the proxy resolver network back to each of the private DNS zones (including the reverse ones) you have created:

    az network private-dns link vnet create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name cloud-managed-dns --zone-name example.com
    az network private-dns link vnet create --subscription 00000000-0000-0000-0000-000000000000 --resource-group DNS --name cloud-managed-dns --zone-name d.f.ip6.arpa
    az network private-dns link vnet create ...

First check that the proxy resolvers are working (they may take a few minutes to start for the first time) by running the following command from a workstation holding one of the IP addresses you listed in `allowed_ips` earlier in `setup.hcl`:

    dig @192.0.2.4 SOA example.com

Where `192.0.2.4` is one of the IPs return earlier in `proxy-ipv6` and `proxy-ipv4`.

The output should look like the following, where if you see `azureprivatedns.net.` then everything is working:

    ; <<>> DiG 9.16.27-Debian <<>> @192.0.2.4 SOA example.com
    ; (1 server found)
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 23510
    ;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;example.com.                    IN      SOA
    
    ;; ANSWER SECTION:
    example.com.             1800    IN      SOA     azureprivatedns.net. azureprivatedns-host.microsoft.com. 1 3600 300 2419200 10
    
    ;; Query time: 36 msec
    ;; SERVER: 192.0.2.4#53(192.0.2.4)
    ;; WHEN: Tue May 10 16:09:27 BST 2022
    ;; MSG SIZE  rcvd: 128

If it does not work:

  * verify your [external IP for the workstation](https://developers.cloudflare.com/1.1.1.1/) is in `allowed_ips` using:

        dig CH TXT whoami.cloudflare @1.1.1.1
        dig CH TXT whoami.cloudflare @2606:4700:4700::1111
  * check that a local firewall is not blocking you directing querying non-local DNS servers
  * check there were no deployment errors, if there were, retry that process until there are no errors

If you have populated your private zone, then you should be able to see your expected result for it with:

    dig @192.0.2.4 server.example.com

**N.B.** any query not for your domains the proxy will return a `REFUSED` status and no results.

### From the Proxy

If you are SSHed into the proxy resolver, you instead would use:

    dig @168.63.129.16 server.example.com

**N.B.** do not change [`168.63.129.16` here as it is Azure's DNS server for local systems](https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16)

## Placing into Production

FIXME...

 * **`nameservers`:** nameservers to use when going live for your domain
     * instruct your domain name registrar to set the NS records of your domain to the values returned for your deployment

# Monitoring

...[work in progress](https://github.com/corememltd/cloud-managed-dns/issues/1)

# Decommissioning

**N.B.** Works in Progress

To remove the in production deployment, simply run from within the project directory:

    make undeploy

A few items are purposely protected and will require manual deletion:

 * Azure DNS (public) hosting
     * nameservers entries will change when re-created, mismatches what you told the domain name registrar to use, your domain is now dead for typically 48 hours until DNS propagation completes
     * retained so you may just re-use the existing resource with no outage
 * public IPv4 and IPv6 addresses of the proxy resolvers
     * by recycling the resources you do not need to reconfigure any on-premises resolvers

If you really want to remove these resources, delete them via the web portal or CLI.

**N.B.** do *not* delete the `terraform.tfstate` file unless you have deleted the whole resource group

## Multiple Administrators

If you are going to be the only administrator tasked with provisioning and/or decommissioning the service (this is *not* the same as administrators of the zone files) you may ignore this section.

This project uses Terraform which unfortunately needs to store information locally that describes the existing cloud deployment, it does this by storing its state in a file named `terraform.tfstate`.

Only a single person may use the deploy and decommissioning process below at a time, and when doing so you must pass around the latest version of the `terraform.tfstate` around your team. There are several ways that you may use in which to do this, and of course every team is different, but I would recommend either:

 * [recommended] store the [`.tfstate` file in Azure Storage](https://learn.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage?tabs=azure-cli)
 * fork this project, edit `.gitignore` to no longer ignore `terraform.tfstate` by adding `!terraform.tfstate` *after* the existing `terraform.tfstate*` entry, commit the state to the project
 * store the file on some networking resource (eg. Microsoft Windows/Samba share, NFS, SFTP, Dropbox, ...)


