#!/usr/bin/perl
# Runs a real Unbound on a scratch configuration and checks that an apply which
# makes it stop puts back the last configuration it ran with and starts it
# again. Needs root, Webmin in /opt/webmin with this module in
# /opt/webmin/unbound, and the unbound binary.
use strict;
use warnings;
use File::Temp qw(tempdir);
our (%config, $module_config_directory);
my $fails = 0;
sub ok { my ($c, $m) = (scalar(shift), shift); print(($c ? "ok  " : "FAIL")." $m\n"); $fails++ if (!$c); return $c; }

my $unbound = "/usr/sbin/unbound";
if (!-x $unbound || $> != 0) {
	print "unbound or root missing, so the rollback test is skipped\n";
	exit(0);
	}
my $tmp = tempdir(CLEANUP => 1);
chmod(0755, $tmp);
my $conf = "$tmp/unbound.conf";
my $good = <<"EOF";
server:
	interface: 127.0.0.1
	port: 5399
	username: ""
	chroot: ""
	directory: "$tmp"
	pidfile: "$tmp/unbound.pid"
	use-syslog: no
	logfile: "$tmp/unbound.log"
	do-daemonize: yes
	module-config: "iterator"
	local-zone: "lan." static
	local-data: "nas.lan. IN A 192.168.1.10"
EOF
sub write_conf { open(my $fh, ">", $conf) || die; print $fh @_; close($fh); }
sub read_conf { open(my $fh, "<", $conf) || die; local $/; return <$fh>; }
write_conf($good);

chdir("/opt/webmin/unbound");
$ENV{'WEBMIN_CONFIG'} = "/etc/webmin"; $ENV{'WEBMIN_VAR'} = "/var/webmin";
$0 = "/opt/webmin/unbound/rollback.pl";
require './unbound-lib.pl';
$module_config_directory = "$tmp/mc";
mkdir($module_config_directory, 0700);
%config = ( %config,
	    'unbound_conf' => $conf, 'add_file' => '', 'init_script' => '',
	    'unbound' => $unbound,
	    'unbound_checkconf' => "/usr/sbin/unbound-checkconf",
	    'unbound_control' => '', 'pid_file' => "$tmp/unbound.pid",
	    'forwarder_flush' => 0, 'check_on_save' => 1,
	    'apply_rollback' => 1 );

sub stop_all
{
my $pid = &is_unbound_running();
kill('TERM', $pid) if ($pid);
sleep(1);
}

my $err = &start_unbound();
ok(!$err, "Unbound starts on the scratch configuration") || print "$err\n";
ok(-r "$module_config_directory/lastgood/index", "a working start is saved as the last good configuration");

# An address this system doesn't have (like after an IP change) : unbound-
# checkconf lets it through, but Unbound exits because it can't listen on it.
# Some checkconf versions also miss a missing auth-zone file, which has the
# same effect.
my $bad = $good;
$bad =~ s/interface: 127.0.0.1/interface: 192.0.2.77/;

# Changed through the module : a reload would keep the old socket and only
# fail at the next reboot, so the change asks for a full restart
$config{'apply_mode'} = "reload";
&restart_needed(0);
&begin_change();
&save_server("interface", [ "192.0.2.77" ]);
&commit_change();
ok(&restart_needed(), "a new listening address asks for a full restart");
foreach my $how ("module", "file") {
	if ($how eq 'file') {
		# Edited by hand, then applied with a full restart
		write_conf($bad);
		&clear_config_cache();
		&restart_needed(1);
		}
	$err = &apply_configuration();
	my $said = $err && index($err, "$module_config_directory/failed") >= 0;
	ok($said, "$how : the failed apply says the configuration was put back") ||
		print(($err || "no error")."\n");
	ok(&is_unbound_running(), "$how : Unbound is running again");
	ok(read_conf() eq $good, "$how : the configuration file is the good one again");
	ok(-r "$module_config_directory/failed/index", "$how : the failed configuration is kept");
	}

# A good change is applied and becomes the new last good configuration
my $better = $good."\tlocal-data: \"pi.lan. IN A 192.168.1.2\"\n";
write_conf($better);
&clear_config_cache();
&restart_needed(0);
$config{'apply_mode'} = "reload";
$err = &apply_configuration();
ok(!$err, "a good change applies") || print "$err\n";
ok(&is_unbound_running(), "Unbound runs with the good change");
my %idx;
&read_file("$module_config_directory/lastgood/index", \%idx);
my ($n) = grep { $idx{$_} eq $conf } keys %idx;
ok($n && &read_file_contents("$module_config_directory/lastgood/$n") eq $better,
   "the good change is now the last good configuration");

# With the option off, nothing is put back
write_conf($bad);
&clear_config_cache();
&restart_needed(1);
$config{'apply_rollback'} = 0;
$err = &apply_configuration();
ok($err && $err !~ /failed/, "with rollback off the error is reported only");
ok(read_conf() eq $bad, "with rollback off the configuration is left as it is");

stop_all();
print $fails ? "$fails rollback test(s) FAILED\n" : "rollback tests passed\n";
exit($fails ? 1 : 0);
