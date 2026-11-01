#!/bin/sh
# Runs the parser and writer tests against a fresh copy of the fixture.
# Needs Webmin installed in /opt/webmin with this module in /opt/webmin/unbound.
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
cp -a "$here/fixture/." "$tmp/"
perl "$here/parser.pl" "$tmp"
rc=$?
perl "$here/json.pl" || rc=1
perl "$here/labels.pl" || rc=1
perl "$here/resolver.pl" || rc=1
perl "$here/cgi.pl" || rc=1
perl "$here/pihole.pl" || rc=1
perl "$here/rollback.pl" || rc=1
rm -rf "$tmp"
exit $rc
