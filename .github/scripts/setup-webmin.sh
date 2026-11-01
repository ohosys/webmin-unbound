#!/bin/sh
# Installs Webmin's sources in /opt/webmin with this module in
# /opt/webmin/unbound, plus the minimal configuration the tests need.
# Used by the GitHub Actions workflows; needs root.
set -e
repo=$(cd "$(dirname "$0")/../.." && pwd)
if [ ! -d /opt/webmin/.git ]; then
	git clone -q --depth 1 https://github.com/webmin/webmin.git /opt/webmin
fi
rm -rf /opt/webmin/unbound
cp -a "$repo/unbound" /opt/webmin/unbound
mkdir -p /etc/webmin/unbound /var/webmin
cat > /etc/webmin/config <<EOF
os_type=debian-linux
os_version=12
real_os_type=Debian Linux
real_os_version=12
lang=en
EOF
echo "root=/opt/webmin" > /etc/webmin/miniserv.conf
cp /opt/webmin/unbound/config-debian-linux /etc/webmin/unbound/config
# The Debian/Ubuntu package config uses this trust anchor, which the service
# normally creates on its first start
if [ ! -s /var/lib/unbound/root.key ] && [ -s /usr/share/dns/root.key ]; then
	mkdir -p /var/lib/unbound
	cp /usr/share/dns/root.key /var/lib/unbound/root.key
fi
