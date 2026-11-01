#!/usr/bin/perl
# Runs the module's pages as CGI programs against a scratch configuration:
# every page must render without a Webmin error, and some saves must change
# the right lines. Needs root, Webmin in /opt/webmin with this module in
# /opt/webmin/unbound (see .github/scripts/setup-webmin.sh) and unbound-checkconf.
use strict;
use warnings;
use File::Temp qw(tempdir);
my $mod = "/opt/webmin/unbound";
my $cfile = "/etc/webmin/unbound/config";
my $fails = 0;
sub ok { my ($c, $m) = (scalar(shift), shift); print(($c ? "ok  " : "FAIL")." $m\n"); $fails++ if (!$c); return $c; }

# Scratch Unbound config, with no blank lines between clauses
my $tmp = tempdir(CLEANUP => 1);
my $conf = "$tmp/unbound.conf";
sub write_conf
{
open(my $fh, ">", $conf) || die "$conf: $!";
print $fh <<'EOF';
server:
	interface: 127.0.0.1
	port: 5335
	local-zone: "lan." static
	local-data: "nas.lan. IN A 192.168.1.10"
	access-control: 192.168.1.0/24 allow
forward-zone:
	name: "example.org."
	forward-addr: 1.1.1.1
stub-zone:
	name: "corp."
	stub-addr: 10.0.0.1
EOF
close($fh);
}
sub read_conf { open(my $fh, "<", $conf) || die; local $/; return <$fh>; }

# Point the module at it, keeping the real module config to put back
open(my $in, "<", $cfile) || die "$cfile: $!";
my $saved = do { local $/; <$in> };
close($in);
my $test = $saved;
$test =~ s/^(unbound_conf|add_file|check_on_save)=.*\n//mg;
$test .= "unbound_conf=$conf\nadd_file=\ncheck_on_save=1\n";
open(my $out, ">", $cfile) || die; print $out $test; close($out);
END {
	if (defined($saved)) {
		open(my $fh, ">", $cfile); print $fh $saved; close($fh);
		}
	}

# run(script, query, [post-body]) : returns the page text
sub run
{
my ($script, $query, $body) = @_;
my $method = defined($body) ? "POST" : "GET";
$body //= "";
local %ENV = ( %ENV,
	WEBMIN_CONFIG => "/etc/webmin", WEBMIN_VAR => "/var/webmin",
	SERVER_ROOT => "/opt/webmin",
	SCRIPT_FILENAME => "$mod/$script", SCRIPT_NAME => "/unbound/$script",
	REMOTE_USER => "root", BASE_REMOTE_USER => "root",
	REQUEST_METHOD => $method, QUERY_STRING => $query,
	SERVER_NAME => "localhost", SERVER_PORT => "10000",
	HTTP_REFERER => "https://localhost:10000/unbound/",
	CONTENT_TYPE => "application/x-www-form-urlencoded",
	CONTENT_LENGTH => length($body) );
my $tmpin = "$tmp/body";
open(my $b, ">", $tmpin) || die; print $b $body; close($b);
my $page = `cd $mod && perl $script < $tmpin 2>&1`;
return $page;
}
sub text_of { my ($p) = @_; $p =~ s/<script.*?<\/script>//gs; $p =~ s/<[^>]+>/ /g; $p =~ s/\s+/ /g; return "PAGE: ".substr($p, 0, 1500)."\n"; }
sub failed { my ($p) = @_; return $p =~ /Access denied|<title>[^<]*Error|<h1>Error|Error\s*:|Failed to|Security Warning/ ? 1 : 0; }

# Every page renders
&write_conf();
foreach my $p ([ "index.cgi", "" ], [ "check.cgi", "" ], [ "control.cgi", "" ],
	       [ "edit_access.cgi", "" ], [ "edit_local.cgi", "zone=lan." ],
	       [ "edit_local.cgi", "new=1&type=static" ],
	       [ "edit_record.cgi", "zone=lan.&new=1&type=A" ],
	       [ "edit_fwd.cgi", "type=forward&name=example.org." ],
	       [ "edit_fwd.cgi", "type=stub&name=corp." ],
	       [ "edit_fwd.cgi", "type=forward&new=1" ],
	       [ "edit_auth.cgi", "new=1" ], [ "edit_rpz.cgi", "new=1" ],
	       [ "edit_view.cgi", "new=1" ], [ "edit_batch.cgi", "" ],
	       [ "edit_manual.cgi", "" ],
	       map { [ "edit_opts.cgi", "page=$_" ] } qw(net perf sec log rc)) {
	my $page = &run(@$p);
	&ok(scalar(!&failed($page) && $page =~ /<\/html>|pre_footer_hr/i), "page $p->[0]?$p->[1]");
	}

# Replacing a forward zone's addresses with a host removes the old address
# and keeps the new line inside the same zone
&write_conf();
my $page = &run("save_fwd.cgi", "", "type=forward&old=example.org.&".
		"name=example.org.&addrs=&hosts=dns.quad9.net&first=&tls=&nocache=");
my $c = &read_conf();
&ok(!&failed($page), "save_fwd: saved") || print &text_of($page);
&ok($c !~ /forward-addr: 1.1.1.1/, "save_fwd: emptied address list is removed") ||
	print $c, &text_of($page);
&ok(scalar($c =~ /name: "example.org."\n\tforward-host: dns.quad9.net\nstub-zone:/),
    "save_fwd: new host stays in its own zone") || print $c;

# Adding a record puts it in server:
&write_conf();
$page = &run("save_record.cgi", "", "zone=lan.&new=1&type=A&name=pc&ttl_def=1&value=192.168.1.20");
$c = &read_conf();
&ok(!&failed($page), "save_record: saved");
&ok(scalar($c =~ /^server:\n(?:\t[^\n]*\n)*?\tlocal-data: "pc\.lan\.[^\n]*192\.168\.1\.20"\n(?:\t[^\n]*\n)*forward-zone:/),
    "save_record: record added inside server:") || print $c;

# Saving an options page without changing anything leaves the file as it is
# (a quoted value stays quoted, no empty server: clause is added)
sub form_fields
{
my ($page) = @_;
my ($form) = $page =~ /(<form[^>]*save_opts\.cgi.*?<\/form>)/s;
$form ||= $page;
my @f;
my $unesc = sub { my $v = shift; $v =~ s/&quot;/"/g; $v =~ s/&#39;/'/g;
		  $v =~ s/&lt;/</g; $v =~ s/&gt;/>/g; $v =~ s/&amp;/&/g; $v };
while ($form =~ /<input([^>]*)>/g) {
	my $a = $1;
	my ($n) = $a =~ /name=["']([^"']+)/ or next;
	my ($t) = $a =~ /type=["']?(\w+)/; $t = lc($t || "text");
	my ($v) = $a =~ /value=["']([^"']*)/; $v = &$unesc($v // "");
	next if ($t =~ /^(submit|button|reset)$/);
	next if ($t =~ /^(radio|checkbox)$/ && $a !~ /\bchecked\b/);
	push(@f, [ $n, $v ]);
	}
while ($form =~ /<select[^>]*name=["']([^"']+)["'][^>]*>(.*?)<\/select>/gs) {
	my ($n, $opts) = ($1, $2);
	while ($opts =~ /<option[^>]*value=["']([^"']*)["'][^>]*\bselected\b/g) {
		push(@f, [ $n, &$unesc($1) ]);
		}
	}
while ($form =~ /<textarea[^>]*name=["']([^"']+)["'][^>]*>(.*?)<\/textarea>/gs) {
	push(@f, [ $1, &$unesc($2) ]);
	}
return join("&", map { my ($n, $v) = @$_;
		       $v =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge;
		       "$n=$v" } @f);
}
&write_conf();
open(my $q, ">>", $conf) || die;
print $q "remote-control:\n\tcontrol-enable: no\n";
close($q);
{
my $orig = &read_conf();
$orig =~ s/^server:\n/server:\n\tauto-trust-anchor-file: "\/var\/lib\/unbound\/root.key"\n/;
open(my $fh, ">", $conf) || die; print $fh $orig; close($fh);
}
foreach my $pg (qw(net perf sec log rc)) {
	my $before = &read_conf();
	my $body = &form_fields(&run("edit_opts.cgi", "page=$pg"));
	my $page = &run("save_opts.cgi", "", $body);
	my $after = &read_conf();
	&ok(!&failed($page) && $before eq $after,
	    "save_opts page=$pg without changes leaves the file alone") ||
		print "----- before\n$before----- after\n$after-----\n";
	}


# Reverse records follow their A record when it is changed or deleted
sub rec_form
{
my ($name) = @_;
my $page = &run("edit_local.cgi", "zone=lan.");
my $q;
while ($page =~ /href=["']edit_record\.cgi\?([^"']+)["'][^>]*>\s*\Q$name\E\s*</g) {
	my $l = $1; $l =~ s/&amp;/&/g;
	if ($l =~ /id=/) { $q = $l; last; }
	}
return ( ) if (!$q);
my $form = &run("edit_record.cgi", $q);
my ($id) = $form =~ /name=["']id["'][^>]*value=["']([^"']*)/;
my ($old) = $form =~ /name=["']old["'][^>]*value=["']([^"']*)/;
foreach my $v ($id, $old) {
	$v =~ s/&quot;/"/g; $v =~ s/&#39;/'/g; $v =~ s/&amp;/&/g;
	}
return ( $id, $old );
}
sub enc { my $v = shift; $v =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge; return $v; }
&write_conf();
&run("save_record.cgi", "", "zone=lan.&new=1&type=A&name=pc&ttl_def=1&value=192.168.1.20&rev=1");
$c = &read_conf();
&ok(scalar($c =~ /local-data-ptr: "192\.168\.1\.20 pc\.lan\."/), "save_record: reverse record added") || print $c;
my ($rid, $rold) = &rec_form("pc");
&ok(scalar($rid), "edit_record: form for the A record found");
$page = &run("save_record.cgi", "", "zone=lan.&new=&type=A&id=".&enc($rid)."&old=".&enc($rold)."&name=pc&ttl_def=1&value=192.168.1.21");
$c = &read_conf();
&ok(scalar(!&failed($page) && $c =~ /local-data-ptr: "192\.168\.1\.21 pc\.lan\."/ && $c !~ /192\.168\.1\.20/),
    "save_record: reverse record moved to the new address") || print $c, &text_of($page);
($rid, $rold) = &rec_form("pc");
$page = &run("save_record.cgi", "", "zone=lan.&new=&type=A&id=".&enc($rid)."&old=".&enc($rold)."&delete=1");
$c = &read_conf();
&ok(scalar(!&failed($page) && $c !~ /local-data-ptr/ && $c !~ /pc\.lan/),
    "save_record: deleting the A record also deletes its reverse record") || print $c, &text_of($page);

# Bulk import : dotted names are complete, short targets go in the zone, and
# a replaced record takes its reverse record with it
&write_conf();
&run("save_batch.cgi", "", "zone=lan.&source=text&format=hosts&text=".&enc("192.168.1.30 box")."&ptr=1&dup=skip&ttl_def=1&import=1");
&ok(scalar(&read_conf() =~ /local-data-ptr: "192\.168\.1\.30 box\.lan\."/), "save_batch: reverse record imported");
$page = &run("save_batch.cgi", "", "zone=lan.&source=text&format=rr&text=".
	&enc("mx1.lan A 192.168.1.40\n\@ MX 10 mx1\nwww CNAME box\n_sip._tcp SRV 1 2 5060 box\nbox A 192.168.1.31").
	"&ptr=0&dup=replace&ttl_def=1&import=1");
$c = &read_conf();
&ok(scalar(!&failed($page)), "save_batch: imported") || print &text_of($page);
&ok(scalar($c =~ /"mx1\.lan\. IN A 192\.168\.1\.40"/), "save_batch: name with a dot is complete") || print $c;
&ok(scalar($c =~ /"lan\. IN MX 10 mx1\.lan\."/), "save_batch: MX target put in the zone") || print $c;
&ok(scalar($c =~ /"www\.lan\. IN CNAME box\.lan\."/), "save_batch: CNAME target put in the zone") || print $c;
&ok(scalar($c =~ /"_sip\._tcp\.lan\. IN SRV 1 2 5060 box\.lan\."/), "save_batch: SRV target put in the zone") || print $c;
&ok(scalar($c =~ /"box\.lan\. IN A 192\.168\.1\.31"/ && $c !~ /192\.168\.1\.30/),
    "save_batch: replaced record's reverse record removed") || print $c;
$page = &run("save_batch.cgi", "", "zone=lan.&source=text&format=rr&text=".&enc("bad MX x")."&ptr=0&dup=skip&ttl_def=1&preview=1");
&ok(scalar($page =~ /reject 1 invalid/i), "save_batch: MX without preference rejected") || print &text_of($page);

# Deleting forward zones from the list leaves no private-domain or
# domain-insecure behind
&write_conf();
&run("save_fwd.cgi", "", "type=forward&new=1&old=&name=home.arpa&addrs=192.168.1.1&hosts=&first=&tls=&nocache=&privdom=1&insecure=1");
$c = &read_conf();
&ok(scalar($c =~ /private-domain: "home\.arpa"/), "save_fwd: private-domain added") || print $c;
$page = &run("delete_zones.cgi", "", "type=forward&d=home.arpa.&delete=1");
$c = &read_conf();
&ok(scalar(!&failed($page) && $c !~ /home\.arpa/), "delete_zones: zone and its private-domain/domain-insecure removed") || print $c, &text_of($page);

# A TLS authentication name needs TLS, and survives editing
&write_conf();
$page = &run("save_fwd.cgi", "", "type=forward&new=1&old=&name=quad9.test&addrs=".&enc("9.9.9.9\@853#dns.quad9.net")."&hosts=&first=&tls=&nocache=&privdom=0&insecure=0");
&ok(scalar($page =~ /DNS-over-TLS/ && &read_conf() !~ /quad9/), "save_fwd: #name without TLS rejected") || print &text_of($page);
$page = &run("save_fwd.cgi", "", "type=forward&new=1&old=&name=quad9.test&addrs=".&enc("9.9.9.9\@853#dns.quad9.net")."&hosts=&first=&tls=yes&nocache=&privdom=0&insecure=0");
my $fform = &run("edit_fwd.cgi", "type=forward&name=quad9.test.");
&ok(scalar(!&failed($page) && $fform =~ /9\.9\.9\.9\@853#dns\.quad9\.net/), "edit_fwd: TLS name kept when the zone is shown again") || print &read_conf();

# Auth zones need their zone file when nothing downloads it
&write_conf();
$page = &run("save_auth.cgi", "", "new=1&old=&name=auth.test&primaries=&urls=&notify=&zonefile_def=0&zonefile=/nonexistent/auth.zone&downstream=&upstream=&fallback=");
&ok(scalar($page =~ /does not exist/ && &read_conf() !~ /auth-zone/), "save_auth: missing zone file rejected") || print &text_of($page);

# RPZ : deleting the last one takes respip out of module-config again
&write_conf();
my $zf = "$tmp/rpz.zone";
open(my $zfh, ">", $zf) || die; print $zfh "\$ORIGIN rpz.test.\n\@ 3600 IN SOA a. b. 1 3600 600 86400 300\n\@ 3600 IN NS localhost.\n"; close($zfh);
$page = &run("save_rpz.cgi", "", "new=1&old=&name=rpz.test&urls=&primaries=&zonefile_def=0&zonefile=".&enc($zf)."&action=&cname_def=1&cname=&log=&logname_def=1&logname=&ra=");
$c = &read_conf();
&ok(scalar(!&failed($page) && $c =~ /module-config: "respip/), "save_rpz: respip added") || print $c, &text_of($page);
$page = &run("delete_zones.cgi", "", "type=rpz&d=rpz.test.&delete=1");
$c = &read_conf();
&ok(scalar(!&failed($page) && $c !~ /respip/ && $c !~ /rpz:/), "delete_zones: respip removed with the last RPZ") || print $c, &text_of($page);

# webmin.conf in an included directory is only created when something goes in it
my $cdir = "$tmp/conf.d";
mkdir($cdir);
unlink("$cdir/webmin.conf");
open(my $ifh, ">", $conf) || die; print $ifh "server:\n\tinterface: 127.0.0.1\n\tport: 5335\ninclude: \"$cdir/*.conf\"\n"; close($ifh);
$page = &run("save_auth.cgi", "", "new=1&old=&name=auth.test&primaries=&urls=&notify=&zonefile_def=0&zonefile=/nonexistent/auth.zone&downstream=&upstream=&fallback=");
&ok(scalar(&failed($page) && !-e "$cdir/webmin.conf"), "failed save leaves no empty webmin.conf") || print &text_of($page);
$page = &run("save_fwd.cgi", "", "type=forward&new=1&old=&name=new.test&addrs=1.1.1.1&hosts=&first=&tls=&nocache=&privdom=0&insecure=0");
my $wc = -e "$cdir/webmin.conf" ? do { local $/; open(my $w, "<", "$cdir/webmin.conf"); <$w> } : "";
&ok(scalar(!&failed($page) && $wc =~ /name: "new\.test\."/), "new zone goes into webmin.conf in the included directory") || print $wc, &text_of($page);
unlink("$cdir/webmin.conf");

# Pages that change Pi-hole only act on a POST from their own form
$page = &run("pihole_domain.cgi", "quick=deny/exact/ads.example.com&return=queries");
&ok(scalar($page =~ /only accepts changes sent from its form/), "pihole_domain: a GET link changes nothing") || print &text_of($page);
$page = &run("pihole_list.cgi", "", "add=1&type=block&address=".&enc("file:///etc/shadow")."&comment=");
&ok(scalar($page =~ /is not a http/), "pihole_list: file:// outside the allowed directories rejected") || print &text_of($page);
$page = &run("pihole_list.cgi", "", "add=1&type=block&address=".&enc("file:///etc/pihole/../shadow")."&comment=");
&ok(scalar($page =~ /is not a http/), "pihole_list: file:// with .. rejected") || print &text_of($page);

print $fails ? "\n$fails CGI test(s) FAILED\n" : "\nCGI tests passed\n";
exit($fails ? 1 : 0);
