#!/bin/sh

set -eu

export DEBIAN_FRONTEND=noninteractive
{
	echo tzdata tzdata/Areas select Etc;
	echo tzdata tzdata/Zones/Etc select UTC;
} | debconf-set-selections

# ubuntu prunes docs and we need the m4 example foreachq.m4 and its dependencies
if [ -f /etc/dpkg/dpkg.cfg.d/excludes ]; then
	rm /etc/dpkg/dpkg.cfg.d/excludes
fi

apt-get update
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		--option=Dpkg::options::=--force-unsafe-io upgrade --no-install-recommends
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		--option=Dpkg::options::=--force-unsafe-io install --no-install-recommends \
	m4 \
	unbound
#apt-get -y autoremove
apt-get clean
#find /var/lib/apt/lists -type f -delete

cat <<'EOF' > /etc/unbound/unbound.conf.d/listen.conf
server:
    interface: eth0
    interface: 127.0.0.1
    access-control: 0.0.0.0/0 allow
    access-control: ::/0 allow
    access-control: 127.0.0.0/8 allow_snoop
    access-control: ::1 allow_snoop
EOF

cat <<'EOF' | m4 -I /usr/share/doc/m4/examples -D DOMAINS="$DOMAINS" -D NSS="$NSS" > /etc/unbound/unbound.conf.d/zone.conf
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#term-domain-insecure-domain-name
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#forward-zone-options
include(`foreachq.m4')dnl
dnl
server:
foreachq(`DOMAIN', `DOMAINS', `    domain-insecure: "DOMAIN."
')dnl

foreachq(`DOMAIN', `DOMAINS', `forward-zone:
    name: DOMAIN
foreachq(`NS', `NSS', `    forward-addr: NS
')dnl
')dnl
EOF

cat <<'EOF' > /etc/unbound/unbound.conf.d/stale.conf
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#unbound-conf-serve-expired
server:
    serve-expired: yes
    serve-expired-ttl: 86400
    serve-expired-client-timeout: 1800
EOF

systemctl enable unbound
systemctl restart unbound

exit 0
