#!/bin/sh

set -eu

VENDOR=coremem
PROJECT=cloud-managed-dns

apt update
apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		--option=Dpkg::options::=--force-unsafe-io upgrade --no-install-recommends
apt -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		--option=Dpkg::options::=--force-unsafe-io install --no-install-recommends \
	git \
	unbound
apt -y autoremove
apt clean
find /var/lib/apt/lists -type f -delete

if [ -d /opt/$VENDOR/$PROJECT ]; then
	git -C /opt/$VENDOR/$PROJECT reset --hard
	git -C /opt/$VENDOR/$PROJECT pull origin HEAD
else
	mkdir /opt/$VENDOR
	git clone /tmp/$VENDOR-$PROJECT.git /opt/$VENDOR/$PROJECT
fi

shred -u /tmp/$VENDOR-$PROJECT.git

mkdir -p "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d"

cat <<'EOF' > "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d/listen.conf"
server:
    interface: eth0
    interface: 127.0.0.1
    access-control: 0.0.0.0/0 allow
    access-control: ::/0 allow
    access-control: 127.0.0.0/8 allow_snoop
    access-control: ::1 allow_snoop
EOF

# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#term-domain-insecure-domain-name
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#term-local-zone-zone-type
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#forward-zone-options
cat <<'EOF' > "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d/zone.conf"
server:
    domain-insecure: "soas.ac.uk."

    local-zone: "." always_refuse
    local-zone: "soas.ac.uk." always_transparent

# must use forward-zone as stub-zone turns off RD and upstream returns REFUSED
forward-zone:
    name: soas.ac.uk
    forward-no-cache: yes
    # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
    forward-addr: 168.63.129.16
EOF

find "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d" -type f -print0 | xargs -0 -r -t ln -f -t /etc/unbound/unbound.conf.d

unbound-checkconf

exit 0
