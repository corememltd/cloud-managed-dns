# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#term-domain-insecure-domain-name
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#term-local-zone-zone-type
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#forward-zone-options
include(`foreachq.m4')dnl
dnl
server:
foreachq(`DOMAIN', `DOMAINS', `    domain-insecure: "DOMAIN."
')dnl

    local-zone: "." always_refuse
foreachq(`DOMAIN', `DOMAINS', `    local-zone: "DOMAIN." always_transparent
')dnl

# must use forward-zone as stub-zone turns off RD and upstream returns REFUSED
# https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
foreachq(`DOMAIN', `DOMAINS', `forward-zone:
    name: DOMAIN
    forward-no-cache: yes
    forward-addr: 168.63.129.16
')dnl
