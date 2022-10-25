Deploy and managed your authoritative DNS service with your cloud provider (currently only Azure) with support for [split-horizon DNS](https://en.wikipedia.org/wiki/Split-horizon_DNS) and on-premise recursive resolvers.

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

This project currently requires that you are using it on one of the following Operating Systems:

 * [Debian](https://debian.org/) 11 (bullseye) - tested
 * [Ubuntu](https://ubuntu.com/) 22.04 (jammy) and later
 * [Microsoft WSL 2](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
 * macOS

You will require pre-installed:

 * [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/)
     * have access to the Azure subscription you wish to deploy to
 * `curl`
 * `dig` ([Tutorial](https://phoenixnap.com/kb/linux-dig-command-examples)) - part of the Debian/Ubuntu `bind9-dnsutils` package
 * `git`
 * `gmake` - GNU `make`
     * macOS users need to use `gmake` where the instructions below describe that you need to type `make`
 * `ssh`
 * `unzip`

Check out this project and enter the project directory with:

    git clone https://github.com/corememltd/cloud-managed-dns.git
    cd cloud-managed-dns

Start by logging into Azure via the CLI by running:

    az login

List the subscriptions you have access to with:

    az account list --output table

Pin the deployment to the [subscription of your choosing](https://docs.microsoft.com/en-us/azure/azure-portal/get-subscription-tenant-id) with (replacing `00000000-0000-0000-0000-000000000000` with your subscription ID):

    az account show --subscription 00000000-0000-0000-0000-000000000000 > account.json

The contents of this file should describe your selected subscription and the tenant it is part of.

Using the example configuration file as a template:

    cp setup.hcl.example setup.hcl

Now edit `setup.hcl` to set at least the following to your needs:

 * **`domains` (required):** list of one or more domains you are hosting
 * **`location` (default: `uksouth`):** [region with availability zones](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones) nearest to your on-premise deployment
 * **`allowed_ips` (required):** this must encompass at least the (public) IPs of your on-premises DNS resolvers

## Multiple Administrators

If you are going to be the only administrator provisioning and/or decommissioning (this does *not* include multiple zone file administrators) the service you can ignore this section.

This project uses Terraform which unfortunately needs to store information locally to it that describes any existing cloud deployment it has maintained, it does this by using a file named `terraform.tfstate` to store its state in.

Only a single person may use the deploy and decommissioning process below at any one time, and you must pass around the `terraform.tfstate` around your team once finished.

Every site deployment is different, but I would recommend either:

 * fork this project, edit `.gitignore` to no longer ignore `terraform.tfstate` by adding `!terraform.tfstate` *after* the existing `terraform.tfstate*` entry, commit the state to the project
 * store the file on some networking resource (eg. Microsoft Windows/Samba share, Azure storage account, ...)

# Deploy

Whilst following the below deploy process, early into it you may see it stall with something like the following message:

    ==> azure-arm.main: Microsoft Azure: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ABCD12345 to authenticate.

You should follow the instructions shown there to authorise the CLI tooling to perform tasks using your user credentials.

**N.B.** annoyingly you will need to do this twice one immediately after the other but once done you should be able to walk away and get a coffee

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

You now need to populate your Azure DNS resources with records. You can do this manually via the web portal or CLI, but it is far more reliable where possible to use the Azure zone importing functionality built into the CLI tool.

To use this you will need a copy of your zone file and at least the public view, if not private one too. If you do not have traditional BIND zone files, your existing authoritative DNS server (check the vendor documentation!) should let you generate one via an AXFR query using something like:

    dig AXFR @192.0.2.1 example.invalid | tee example.invalid.axfr

Once you have a zone file, you can import it using (replacing the `-n` and `-f` parameters) depending on the view you are importing:

 * public: `az network dns zone import -g coremem-cloud-managed-dns -n example.invalid -f example.invalid.axfr`
 * private: `az network private-dns zone import -g coremem-cloud-managed-dns -n example.invalid -f example.invalid.axfr`

Once you have imported the records, you should be able to test them as detailed below.

## Recursive DNS (On-Premises)

Each on-premise environment is different, and forcing the administrator to use a given orchestration tool will not fly.

Instead provided is a shell script ([`setup.resolver.sh`](./setup.resolver.sh)) that you should copy to a fresh recent Debian (11.x) or Ubuntu (22.04) based system and run there as `root` the following:

    export DOMAINS=example.com,example.org
    export NSS=192.0.2.1,192.0.2.241,2001:db8::1234,2001:db8::9876
    sh setup.resolver.sh

**N.B.** `DOMAINS` is a list of the domains comma separated you added to `setup.hcl` and `NSS` is the list of all the IPs returned comma separated for the Azure hosted DNS proxies

The configuration installed will serve stale records for up to 24 hours (`/etc/unbound/unbound.conf.d/stale.conf`) in case there is a problem with reaching the upstream Azure hosted proxies.

# Usage and Testing

This section will walk you through testing your service before putting it into production.

Points to be aware of:

 * externally, *only* records in the public view will be returned
 * internally, *only* records in the private view will be returned
     * records from the public view do not back fill
         * this functionality is available in DNS Wingman (send enquires to info@coremem.com)
 * generally you should not put [special use IPs (RFC6890)](https://www.rfc-editor.org/rfc/rfc6890) into the public view
     * so not `192.168.0.0/16` or `fc00::/7`

## Public

Once you have populated your public zone, then you should be able to see your expected result for it with:

    dig @nsA-0Y.azure-dns.com server.example.invalid

Where `nsA-0Y.azure-dns.com` is one of the entries from the `nameservers` output produced earlier.

## Private

First check that the proxy resolvers are working (they may take a few minutes to start for the first time) by running the following command from a workstation holding one of the IP addresses you listed in `allowed_ips` earlier in `setup.hcl`:

    dig @192.0.2.4 SOA example.invalid

Where `192.0.2.4` is one of the IPs return earlier in `proxy-ipv6` and `proxy-ipv4`.

The output should look like the following, where if you see `azureprivatedns.net.` then everything is working:

    ; <<>> DiG 9.16.27-Debian <<>> @192.0.2.4 SOA example.invalid
    ; (1 server found)
    ;; global options: +cmd
    ;; Got answer:
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 23510
    ;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
    
    ;; OPT PSEUDOSECTION:
    ; EDNS: version: 0, flags:; udp: 1232
    ;; QUESTION SECTION:
    ;example.invalid.                    IN      SOA
    
    ;; ANSWER SECTION:
    example.invalid.             1800    IN      SOA     azureprivatedns.net. azureprivatedns-host.microsoft.com. 1 3600 300 2419200 10
    
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

    dig @192.0.2.4 server.example.invalid

**N.B.** any query not for your domains the proxy will return a `REFUSED` status and no results.

### From the Proxy

If you are SSHed into the proxy resolver, you instead would use:

    dig @168.63.129.16 server.example.invalid

**N.B.** do not change [`168.63.129.16` as it is Azure's DNS server for local systems](https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16)

## Placing into Production


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
