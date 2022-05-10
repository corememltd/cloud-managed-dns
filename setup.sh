#!/bin/sh

set -eu

VENDOR=coremem
PROJECT=cloud-managed-dns

apt update
apt -y upgrade
apt -y install --no-install-recommends unbound

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

# https://unbound.docs.nlnetlabs.nl/en/latest/topics/serve-stale.html
cat <<'EOF' > "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d/serve-stale.conf"
server:
    serve-expired: yes
    serve-expired-ttl: 86400            # one day, in seconds
    serve-expired-client-timeout: 1800  # 1.8 seconds, in milliseconds
EOF

# must use forward-zone as stub-zone turns off RD and upstream returns REFUSED
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#term-local-zone-zone-type
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#forward-zone-options
# https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html#stub-zone-options
cat <<'EOF' > "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d/zone.conf"
server:
  local-zone: "." always_refuse
  local-zone: "soas.ac.uk." always_transparent

forward-zone:
    name: soas.ac.uk
    # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
    forward-addr: 168.63.129.16
EOF

find "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d" -type f -print0 | xargs -0 -r -t ln -f -t /etc/unbound/unbound.conf.d

systemctl restart unbound
