#!/usr/bin/perl
# Tests get_resolver_status() on sample resolv.conf files.
# Needs Webmin installed in /opt/webmin with this module in /opt/webmin/unbound.
use File::Temp qw(tempdir);
chdir("/opt/webmin/unbound");
$ENV{'WEBMIN_CONFIG'} = "/etc/webmin"; $ENV{'WEBMIN_VAR'} = "/var/webmin";
$0 = "/opt/webmin/unbound/test.pl";
require './unbound-lib.pl';
my $fails = 0;
sub ok($$) { my ($c, $m) = @_; print(($c ? "ok  " : "FAIL")." $m\n"); $fails++ if (!$c); }

my $tmp = tempdir(CLEANUP => 1);
my $n = 0;
sub status
{
my ($content) = @_;
my $f = "$tmp/resolv".($n++).".conf";
if (defined($content)) {
	open(my $fh, ">", $f) || die "$f: $!";
	print $fh $content;
	close($fh);
	}
return &get_resolver_status($f);
}

my %r = status("");
ok($r{'none'} && $r{'uses_local'}, "empty file: no nameserver, so the local server");
%r = status("# comment only\nsearch lan\n");
ok($r{'none'} && $r{'uses_local'}, "no nameserver line: local server");
%r = status(undef);
ok($r{'none'} && $r{'uses_local'}, "missing file: local server");
%r = status("nameserver 192.0.2.1\n");
ok(!$r{'none'} && !$r{'uses_local'}, "remote nameserver only");
ok(join(",", @{$r{'nameservers'}}) eq "192.0.2.1", "nameserver listed");
%r = status("nameserver 192.0.2.1\nnameserver 127.0.0.1\n");
ok($r{'uses_local'}, "127.0.0.1 among others");
%r = status("nameserver ::1\n");
ok($r{'uses_local'}, "::1");
%r = status("nameserver 127.0.0.53\n");
ok(!$r{'uses_local'}, "systemd-resolved stub is not the local DNS server");
%r = status("  nameserver\t127.0.0.1  \n");
ok($r{'uses_local'}, "spaces and tabs around the address");

print $fails ? "\n$fails FAILED\n" : "\nresolver tests passed\n";
exit($fails ? 1 : 0);
