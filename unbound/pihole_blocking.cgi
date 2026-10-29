#!/usr/local/bin/perl
# Turn Pi-hole blocking on or off, maybe for a limited time

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_err'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});

my $on = $in{'enable'} ? 1 : 0;
my $timer = !$on && $in{'timer'} =~ /^\d+$/ && $in{'timer'} > 0 ?
		int($in{'timer'}) : undef;
my ($d, $err) = &pihole_api("POST", "/dns/blocking",
	{ 'blocking' => $on ? \1 : \0,
	  'timer' => $timer });
&error($err) if ($err);
&webmin_log($on ? "pihole_enable" : "pihole_disable", undef, $timer);
&redirect("pihole.cgi?mode=status");
