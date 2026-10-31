#!/bin/sh
# Compiles every Perl file of the module with perl -c, from inside Webmin
# (after setup-webmin.sh), so a syntax error fails the build.
cd /opt/webmin/unbound || exit 1
rc=0
for f in *.pl *.cgi; do
	out=$(perl -c "$f" 2>&1) || { echo "FAIL $f"; echo "$out"; rc=1; }
done
[ $rc = 0 ] && echo "syntax check passed"
exit $rc
