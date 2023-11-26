#!/bin/sh

set -eu

VENDOR=coremem
PROJECT=cloud-managed-dns

export DEBIAN_FRONTEND=noninteractive
{
	echo tzdata tzdata/Areas select Etc;
	echo tzdata tzdata/Zones/Etc select UTC;
} | debconf-set-selections

apt-get update
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		--option=Dpkg::options::=--force-unsafe-io upgrade --no-install-recommends
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
		--option=Dpkg::options::=--force-unsafe-io install --no-install-recommends \
	git \
	python3-dnspython \
	python3-unbound \
	unattended-upgrades \
	unbound

apt-get -y autoremove
apt-get clean
find /var/lib/apt/lists -type f -delete

# nope...
test ! -f /etc/ssh/sshd_config || sed -i -e 's/^#\?\(PermitRootLogin\) .*/\1 no/' /etc/ssh/sshd_config
rm -rf ~/.ssh

# we only allow direct root logins via /etc/securetty
test -f /etc/securetty || cat <<'EOF' > /etc/securetty
console
ttyS0
EOF
sed -i '1iauth [success=1 default=ignore] pam_securetty.so' /etc/pam.d/login
passwd -d root

mkdir /opt/$VENDOR
git -c advice.detachedHead=false clone /tmp/bundle.git /opt/$VENDOR/$PROJECT
shred -u /tmp/bundle.git

ln -s -t /usr/local/lib/python3.11/dist-packages /usr/lib/python3/dist-packages/unboundmodule.py
# https://github.com/NLnetLabs/unbound/issues/769
cat <<'EOF' > /etc/apparmor.d/local/usr.sbin.unbound
/usr/local/lib/python3.11/dist-packages/ r,
/usr/local/lib/python3.11/dist-packages/** r,
/opt/coremem/cloud-managed-dns/services/unbound/script.py r,
EOF

find "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d" -type f -name '*.conf' -print0 | xargs -0 -r -t ln -f -t /etc/unbound/unbound.conf.d
# https://github.com/NLnetLabs/unbound/issues/574
#unbound-checkconf

exit 0
