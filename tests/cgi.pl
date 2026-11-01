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
sub ok { my ($c, $m) = @_; print(($c ? "ok  " : "FAIL")." $m\n"); $fails++ if (!$c); return $c; }

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
sub failed { my ($p) = @_; return $p =~ /<h1>Error|Error\s*:|Failed to/ ? 1 : 0; }

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
	&ok(!&failed($page) && $page =~ /<\/html>/i, "page $p->[0]?$p->[1]");
	}

# Replacing a forward zone's addresses with a host removes the old address
# and keeps the new line inside the same zone
&write_conf();
my $page = &run("save_fwd.cgi", "", "type=forward&old=example.org.&".
		"name=example.org.&addrs=&hosts=dns.quad9.net&first=&tls=&nocache=");
my $c = &read_conf();
&ok(!&failed($page), "save_fwd: saved");
&ok($c !~ /forward-addr: 1.1.1.1/, "save_fwd: emptied address list is removed");
&ok($c =~ /name: "example.org."\n\tforward-host: dns.quad9.net\nstub-zone:/,
    "save_fwd: new host stays in its own zone") || print $c;

# Adding a record puts it in server:
&write_conf();
$page = &run("save_record.cgi", "", "zone=lan.&new=1&type=A&name=pc&ttl_def=1&value=192.168.1.20");
$c = &read_conf();
&ok(!&failed($page), "save_record: saved");
&ok($c =~ /^server:\n(?:\t[^\n]*\n)*?\tlocal-data: "pc\.lan\.[^\n]*192\.168\.1\.20"\n(?:\t[^\n]*\n)*forward-zone:/,
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

print $fails ? "\n$fails CGI test(s) FAILED\n" : "\nCGI tests passed\n";
exit($fails ? 1 : 0);
