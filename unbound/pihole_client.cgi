#!/usr/local/bin/perl
# Add or delete Pi-hole clients

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_cerr'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});

if ($in{'add'} && $ENV{'REQUEST_METHOD'} eq 'GET') {
	# Link from the network page, so just fill in the form
	&redirect("pihole.cgi?mode=clients&client=".&urlize($in{'client'}));
	exit;
	}
if ($in{'add'}) {
	my $c = $in{'client'};
	$c =~ s/^\s+|\s+$//g;
	&valid_ip($c) || &valid_netblock($c) ||
	  $c =~ /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i || $c =~ /^:[a-z0-9\.\-]+$/i ||
		&error(&text('pihole_eclient', &html_escape($c)));
	my @g = grep { /^\d+$/ } split(/\0/, $in{'groups'});
	my ($d, $err) = &pihole_api("POST", "/clients",
		{ 'client' => $c, 'comment' => $in{'comment'},
		  'groups' => [ map { int($_) } (@g ? @g : (0)) ] });
	&error($err) if ($err);
	&webmin_log("pihole_add", "client", $c);
	}
elsif ($in{'delete'}) {
	my @d = split(/\0/, $in{'d'});
	@d || &error($text{'pihole_enone'});
	foreach my $c (@d) {
		my ($r, $err) = &pihole_api("DELETE", "/clients/".
					    &pihole_path_part($c));
		&error($err) if ($err);
		}
	&webmin_log("pihole_delete", "clients", scalar(@d));
	}
&redirect("pihole.cgi?mode=clients");
