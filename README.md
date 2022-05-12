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
 * [Ubuntu](https://ubuntu.com/) 20.04 (focal) and later
 * [Microsoft WSL 2](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
 * macOS

You will require pre-installed:

 * [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/)
     * have access to the Azure subscription you wish to deploy to
 * `curl`
 * `dig` ([Tutorial](https://phoenixnap.com/kb/linux-dig-command-examples)) - part of the Debian/Ubuntu `bind9-dnsutils` package
 * `git`
 * `gmake` - GNU `make`
 * `ssh`
 * `unzip`

Check out this project and enter the project directory with:

    git clone https://gitlab.com/coremem/cloud-managed-dns.git
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

 * **`domain` (required):** domain you are hosting
 * **`location` (default: `uksouth`):** [region with availability zones](https://docs.microsoft.com/en-us/azure/availability-zones/az-overview#azure-regions-with-availability-zones) nearest to your on-premise deployment
 * **`allowed_ips` (required):** this must encompass at least the (public) IPs of your on-premises DNS resolvers

# Deploy

## Authoritative DNS (Cloud)

Initially we need to build an image for our DNS proxy resolver to run in Azure, this is done with:

    gmake build-proxy

Once the image has been cooked, you can now deploy the infrastructure for this with:

    gmake deploy-authoritative

**N.B.** if you append `DRYRUN=1` to the end, the process will run Terraform in `plan` mode instead of `apply` so no changes will be applied

When the process completes (first run will take at least ten minutes), you will be [returned output](https://www.terraform.io/language/values/outputs) that resembles the *example* below:

    nameservers = toset([
      "nsA-0Y.azure-dns.com.",
      "nsB-0Y.azure-dns.net.",
      "nsC-0Y.azure-dns.org.",
      "nsD-0Y.azure-dns.info.",
    ])
    proxy-ipv6 = [
      "2001:db8:100:8::43",
      "2001:db8:100:8::2e",
    ]
    proxy-ipv4 = [
      "192.0.2.4",
      "192.0.2.79",
    ]

Where:

 * **`nameservers`:** nameservers to use when going live for your domain
     * instruct your domain name registrar to set the NS records of your domain to the values returned for your deployment
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

## Importing

You now need to populate your Azure DNS resources with records. You can do this manually via the web portal or CLI, but it is far more reliable where possible to use the Azure zone importing functionality built into the CLI tool.

To use this you will need a copy of your zone file and at least the public view, if not private one too. If you do not have traditional BIND zone files, your existing authoritative DNS server (check the vendor documentation!) should let you generate one via an AXFR query using something like:

    dig AXFR @192.0.2.1 example.invalid | tee example.invalid.axfr

Once you have a zone file, you can import it using (replacing the `-n` and `-f` parameters) depending on the view you are importing:

 * public: `az network dns zone import -g coremem-cloud-managed-dns -n example.invalid -f example.invalid.axfr`
 * private: `az network private-dns zone import -g coremem-cloud-managed-dns -n example.invalid -f example.invalid.axfr`

Once you have imported the records, you should be able to test them as detailed below.

## Recursive DNS (On-Premises)

...

# Usage and Testing

This section will walk you through testing your service before putting it into production.

Points to be aware of:

 * records in the private view take precedence over the records in the public view
     * externally, if a record exists in the private view but not public, then the response will be `NXDOMAIN`
     * externally, if a record exists in both the private and public views, then the response will be the public one
     * internally, if a record exists in the private view but not public, then the response will be the private one
     * internally, if a record exists in both the private and public views, then the response will be the private one
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

**N.B.** any query not for your domain the proxy will return a `REFUSED` status and no results.

### From the Proxy

If you are SSHed into the proxy resolver, you instead would use:

    dig @168.63.129.16 server.example.invalid

**N.B.** do not change [`168.63.129.16` as it is Azure's DNS server for local systems](https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16)

# Decommissioning

**N.B.** Works in Progress

To remove the in production deployment, simply run from within the project directory:

    gmake undeploy-authoritative

A few items are purposely protected and will require manual deletion:

 * Azure DNS (public) hosting
     * nameservers entries will change when re-created, mismatches what you told the domain name registrar to use, your domain is now dead for typically 48 hours until DNS propagation completes
     * retained so you may just re-use the existing resource with no outage
 * public IPv4 and IPv6 addresses of the proxy resolvers
     * by recycling the resources you do not need to reconfigure any on-premises resolvers

If you really want to remove these resources, delete them via the web portal or CLI.
