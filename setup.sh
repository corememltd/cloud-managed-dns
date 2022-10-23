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
	jq \
	m4 \
	unbound
apt-get -y autoremove
apt-get clean
find /var/lib/apt/lists -type f -delete

if [ -d /opt/$VENDOR/$PROJECT ]; then
	git -C /opt/$VENDOR/$PROJECT reset --hard
	git -C /opt/$VENDOR/$PROJECT pull --ff-only origin HEAD
else
	mkdir /opt/$VENDOR
	git -c advice.detachedHead=false clone /tmp/$VENDOR-$PROJECT.git /opt/$VENDOR/$PROJECT
fi
shred -u /tmp/$VENDOR-$PROJECT.git

find /opt/$VENDOR/$PROJECT/services/systemd -type f | xargs ln -f -s -t /lib/systemd/system
systemctl enable coremem-cloud-managed-dns-unbound.service

find "/opt/$VENDOR/$PROJECT/services/unbound/unbound.conf.d" -type f -name '*.conf' -print0 | xargs -0 -r -t ln -f -t /etc/unbound/unbound.conf.d
# https://github.com/NLnetLabs/unbound/issues/574
#unbound-checkconf

exit 0
