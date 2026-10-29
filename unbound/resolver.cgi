#!/usr/local/bin/perl
# Make this system use Unbound for its own DNS lookups, through the
# Network Configuration module's DNS client settings

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'resolver_err'});
&can_edit('apply') || &error($text{'check_ecannot'});
&foreign_available("net") || &error($text{'resolver_enet'});

my %res = &get_resolver_status();
$res{'resolved'} && &error($text{'resolver_eresolved'});
# /etc/resolv.conf can only use port 53
my $port = &find_server_value("port") || 53;
if ($port != 53) {
	my $fw = &dns_forwarder();
	&error($fw ? &text('resolver_efwd', $port, $fw->{'name'})
		   : &text('resolver_eport', $port));
	}
&is_unbound_running() || &error($text{'stop_erunning'});

# Make sure Unbound really answers before pointing the system at it
my ($ok, $ans, $err) = &test_query("127.0.0.1", "localhost", "A");
$ok || &error(&text('resolver_etest', $err));

if (!$in{'confirm'}) {
	&ui_print_header(undef, $text{'resolver_title'}, "");
	print &text('resolver_rusure',
		join(", ", map { "<tt>".&html_escape($_)."</tt>" }
			       @{$res{'nameservers'}}) || "-"),"<p>\n";
	print &ui_confirmation_form("resolver.cgi", $text{'resolver_rusure2'},
				    [ [ "confirm", 1 ] ],
				    [ [ undef, $text{'resolver_ok'} ] ]);
	&ui_print_footer("check.cgi", $text{'check_title'});
	exit;
	}

&foreign_require("net");
my $dns = &net::get_dns_config();
my @ns = grep { $_ ne '127.0.0.1' && $_ ne '::1' }
	      @{$dns->{'nameserver'} || [ ]};
# Unbound first, the old servers after it as a fallback
$dns->{'nameserver'} = [ '127.0.0.1', @ns ];
&net::save_dns_config($dns);
&webmin_log("resolver");
&redirect("check.cgi");
