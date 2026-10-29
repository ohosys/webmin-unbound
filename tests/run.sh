#!/bin/sh
# Runs the parser and writer tests against a fresh copy of the fixture.
# Needs Webmin installed in /opt/webmin with this module in /opt/webmin/unbound.
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
cp -a "$here/fixture/." "$tmp/"
perl "$here/parser.pl" "$tmp"
rc=$?
perl "$here/json.pl" || rc=1
rm -rf "$tmp"
exit $rc
