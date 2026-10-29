# Unit tests for the unbound-lib.pl parser and writer
my $dir = $ARGV[0] || die "usage: parser.pl <copy-of-fixture-dir>\n";
chdir("/opt/webmin/unbound");
$ENV{'WEBMIN_CONFIG'} = "/etc/webmin"; $ENV{'WEBMIN_VAR'} = "/var/webmin";
$0 = "/opt/webmin/unbound/test.pl";
require './unbound-lib.pl';
$config{'unbound_conf'} = "$dir/main.conf"; $config{'add_file'} = "";
$config{'unbound_checkconf'} = "/usr/sbin/unbound-checkconf";
my $fails = 0;
sub ok($$) { my ($c, $m) = @_; print(($c ? "ok  " : "FAIL")." $m\n"); $fails++ if (!$c); }
my $conf = &get_config();
ok(scalar(@$conf) == 4, "4 clauses parsed");
ok(&find_server_value("verbosity") eq "1", "inline 'server: verbosity: 1'");
ok(&find_server_value("port") eq "5353", "directive from include inside clause");
ok(&find_server_value("do-ip6") eq "no", "clause continues after include");
my ($ld) = &find_server("local-data");
ok($ld->{'values'}->[0] eq 'a.x. IN TXT "has # hash"', "hash inside quotes is not a comment");
ok($ld->{'comment'} eq "# c2", "trailing comment kept");
ok(join(",", map { $_->{'name'} } &list_zone_clauses("forward-zone")) eq "one.,two.", "forward zones");
# Writes
&begin_change();
&save_server("verbosity", [ 3 ]);
&save_server("interface", [ "127.0.0.1", "::1" ]);
&save_server("port", [ ]);
&delete_clause(&find_zone_clause("forward-zone", "one."));
&save_server("access-control", [ "10.0.0.0/8 allow", "192.168.0.0/16 refuse" ]);
&commit_change(1);
my $m = &read_file_contents("$dir/main.conf");
my $p = &read_file_contents("$dir/inc/part.conf");
print "----- main.conf\n$m----- part.conf\n$p-----\n";
ok($m =~ /^server: verbosity: 3$/m, "inline directive updated in place");
ok($m =~ /interface: 127.0.0.1\s+# trailing comment\n\tinterface: ::1\n/, "new value added right after existing one, comment kept");
ok($p !~ /port/, "directive deleted from included file");
ok($p =~ /access-control: 192.168.0.0\/16 refuse/, "new access-control added in included file next to old one");
ok($m !~ /one\./ && $m =~ /two\./, "middle clause deleted, next kept");
ok($m =~ /remote-control:\n\tcontrol-enable: yes/, "later clause intact");
# Re-parse and edit after renumbering
&clear_config_cache();
&begin_change();
&save_directives([ &find_zone_clause("forward-zone", "two.") ], "forward-addr", [ "2.2.2.2", "3.3.3.3" ]);
&save_directives([ (&find_clauses("remote-control"))[0] ], "control-port", [ "8953" ]);
&commit_change(1);
$m = &read_file_contents("$dir/main.conf");
ok($m =~ /forward-addr: 2.2.2.2\n\tforward-addr: 3.3.3.3\n/, "multi-value added in clause");
ok($m =~ /control-interface: 127.0.0.1\n\tcontrol-port: 8953\n?$/, "added at end of last clause");
my @e = &check_config();
print "checkconf: ".(@e ? join("\n", @e) : "no errors")."\n";
# Rollback
my $before = &read_file_contents("$dir/main.conf");
&begin_change();
&save_server("bogus-option", [ "1" ]);
&flush_file_lines();
&rollback_change();
ok(&read_file_contents("$dir/main.conf") eq $before, "rollback restores file");
# Quoting / injection
eval { local $main::error_must_die = 1; &quote_value("a\nb"); };
ok($@ =~ /line breaks/, "newline rejected: ".($@ =~ /line breaks/ ? "yes" : $@));
print $fails ? "\n$fails FAILED\n" : "\nALL PASSED\n";
exit($fails ? 1 : 0);
