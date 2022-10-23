#!/bin/sh

set -eu

DOMAINS=$(cat /var/lib/waagent/CustomData | base64 -d | jq -r '.domains | @tsv' | tr '\t' ',')

m4 -I /usr/share/doc/m4/examples \
	-D DOMAINS="$DOMAINS" \
		/opt/coremem/cloud-managed-dns/services/unbound/unbound.conf.d/zone.conf.m4 \
	> /opt/coremem/cloud-managed-dns/services/unbound/unbound.conf.d/zone.conf

exit 0
