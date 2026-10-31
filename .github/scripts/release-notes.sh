#!/bin/sh
# Prints the release notes for version $1: install instructions, the last
# section of unbound/CHANGELOG, the trademark note and the package checksum ($2).
ver=$1
sum=$2
repo=$(cd "$(dirname "$0")/../.." && pwd)
cat <<EOF
**Install:** download \`unbound.wbm.gz\` (or \`unbound-$ver.wbm.gz\`, the same file) below and use Webmin → Webmin Configuration → Webmin Modules → Install Module → From uploaded file. Do not use the *Source code* archives: they are the whole repository, not the module, and Webmin answers "missing a module.info file".

**Installazione:** scarica \`unbound.wbm.gz\` qui sotto e installalo da Webmin → Moduli Webmin → Installa modulo → Da file caricato. Non usare gli archivi *Source code*: contengono tutto il repository, non il modulo.

---

**What's new in $ver**
EOF
# Lines after the last "---- Changes since" header
awk '/^---- Changes since/ { n = NR } { line[NR] = $0 }
     END { for (i = n + 1; i <= NR; i++) if (line[i] != "") print "- " line[i] }' \
	"$repo/unbound/CHANGELOG"
cat <<EOF

Webmin, Unbound and Pi-hole are trademarks of their respective holders. This is an independent third-party project, not affiliated with or endorsed by them.

SHA-256 \`unbound-$ver.wbm.gz\`: $sum
EOF
