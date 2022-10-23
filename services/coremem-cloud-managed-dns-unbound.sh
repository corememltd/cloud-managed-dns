#!/bin/sh

set -eu

# /var/lib/waagent/CustomData does not get populated for some reason,
# probably as waagent thinks it is still provisioned. Instead we
# extract it from ovf-env.xml
DOMAINS=$(cat /var/lib/waagent/ovf-env.xml | sed -ne 's~.*CustomData>\(.*\)</[^>]*CustomData>.*~\1~ p' | base64 -d | jq -r '.domains | @tsv' | tr '\t' ',')

m4 -I /usr/share/doc/m4/examples \
	-D DOMAINS="$DOMAINS" \
		/opt/coremem/cloud-managed-dns/services/unbound/unbound.conf.d/zone.conf.m4 \
	> /opt/coremem/cloud-managed-dns/services/unbound/unbound.conf.d/zone.conf
ln -f -t /etc/unbound/unbound.conf.d /opt/coremem/cloud-managed-dns/services/unbound/unbound.conf.d/zone.conf

exit 0
