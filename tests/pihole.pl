#!/usr/bin/perl
# Runs the Pi-hole page against a stand-in for the Pi-hole 6 API
# (tests/pihole_mock.py): the Unbound link tab must show how many queries
# Unbound answered, and offer a monitor once Unbound is the only upstream.
# Needs root and the same setup as tests/cgi.pl. Skips if Pi-hole is installed.
use strict;
use warnings;
use File::Temp qw(tempdir);
my $mod = "/opt/webmin/unbound";
my $here = $0; $here =~ s/[^\/]+$//; $here ||= "./";
my $fails = 0;
sub ok { my ($c, $m) = (scalar(shift), shift); print(($c ? "ok  " : "FAIL")." $m\n"); $fails++ if (!$c); return $c; }

if (-e "/etc/pihole") {
	print "Pi-hole is installed here, so the Pi-hole page test is skipped\n";
	exit(0);
	}
my $tmp = tempdir(CLEANUP => 1);
my $port = 18089;
my $replies = "$tmp/replies.json";
sub replies
{
my ($ups, $counts) = @_;
my @u = ( { ip => "blocklist", name => "blocklist", port => -1, count => 50 },
	  { ip => "cache", name => "cache", port => -1, count => 500 } );
push(@u, map { my ($ip, $p) = split(/#/, $_); { ip => $ip, name => $ip,
		port => $p || 53, count => $counts->{$_} } } sort keys %$counts);
my $json = "{".join(",",
	'"/api/auth":{"session":{"valid":true,"sid":null,"validity":-1}}',
	'"/api/info/version":{"version":{"ftl":{"local":{"version":"v6.9"}}}}',
	'"/api/config/dns/upstreams":{"config":{"dns":{"upstreams":['.
		join(",", map { "\"$_\"" } @$ups).']}}}',
	'"/api/config/dns/revServers":{"config":{"dns":{"revServers":[]}}}',
	'"/api/stats/upstreams":{"upstreams":['.join(",", map {
		"{\"ip\":\"$_->{ip}\",\"name\":\"$_->{name}\",\"port\":$_->{port},".
		"\"count\":$_->{count}}" } @u).']}').
	"}";
open(my $fh, ">", $replies) || die; print $fh $json; close($fh);
}

# Fake Pi-hole install, pointed at the stand-in
mkdir("/etc/pihole", 0755) || die "/etc/pihole: $!";
END { system("rm -rf /etc/pihole"); kill('TERM', $main::mockpid) if ($main::mockpid); }
open(my $t, ">", "/etc/pihole/pihole.toml") || die;
print $t "[webserver]\n  port = \"${port}o\"\n";
close($t);
&replies([ "127.0.0.1#5335", "1.1.1.1" ], { "127.0.0.1#5335" => 900, "1.1.1.1" => 100 });
$main::mockpid = fork();
if (!$main::mockpid) {
	exec("python3", "${here}pihole_mock.py", $port, $replies) || die;
	}
sleep(1);

# Unbound address that the page compares with
my $conf = "$tmp/unbound.conf";
open(my $c, ">", $conf) || die;
print $c "server:\n\tinterface: 127.0.0.1\n\tport: 5335\n";
close($c);
my $cfile = "/etc/webmin/unbound/config";
open(my $in, "<", $cfile) || die;
my $saved = do { local $/; <$in> };
close($in);
END { if (defined($saved)) { open(my $fh, ">", $cfile); print $fh $saved; close($fh); } }
my $test = $saved;
$test =~ s/^(unbound_conf|add_file|pihole_api|unbound_addr)=.*\n//mg;
$test .= "unbound_conf=$conf\nadd_file=\n";
open(my $out, ">", $cfile) || die; print $out $test; close($out);
system("rm -rf /var/webmin/unbound/pihole.sid /etc/webmin/unbound/pihole.sid");

sub page
{
local %ENV = ( %ENV,
	WEBMIN_CONFIG => "/etc/webmin", WEBMIN_VAR => "/var/webmin",
	SERVER_ROOT => "/opt/webmin",
	SCRIPT_FILENAME => "$mod/pihole.cgi", SCRIPT_NAME => "/unbound/pihole.cgi",
	REMOTE_USER => "root", BASE_REMOTE_USER => "root",
	REQUEST_METHOD => "GET", QUERY_STRING => "mode=unbound",
	SERVER_NAME => "localhost", SERVER_PORT => "10000",
	HTTP_REFERER => "https://localhost:10000/unbound/" );
my $p = `cd $mod && perl pihole.cgi 2>&1 </dev/null`;
$p =~ s/<script.*?<\/script>//gs;
$p =~ s/<[^>]+>/ /g;
$p =~ s/\s+/ /g;
return $p;
}

# Unbound plus another upstream : 90% share, the other server listed
my $p = &page();
&ok(scalar($p =~ /Queries answered by Unbound 90% \(900 of 1000 /), "share of queries Unbound answered") || print "$p\n";
&ok(scalar($p =~ /Other servers : 1\.1\.1\.1 10%/), "other upstream servers listed");
&ok(scalar($p !~ /Create a monitor in System and Server Status/), "no monitor offered while Pi-hole has another upstream");

# Unbound alone : 100%, and a monitor is offered
&replies([ "127.0.0.1#5335" ], { "127.0.0.1#5335" => 1000 });
$p = &page();
&ok(scalar($p =~ /Queries answered by Unbound 100% \(1000 of 1000 /), "Unbound answers everything");
&ok(scalar($p =~ /Create a monitor in System and Server Status/), "monitor offered once Unbound is the only upstream") || print "$p\n";

print $fails ? "\n$fails Pi-hole test(s) FAILED\n" : "\nPi-hole page tests passed\n";
exit($fails ? 1 : 0);
