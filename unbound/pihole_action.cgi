#!/usr/local/bin/perl
# Run a Pi-hole action : update gravity or restart its DNS server

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_err'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});

if ($in{'action'} eq 'restartdns') {
	my ($d, $err) = &pihole_api("POST", "/action/restartdns");
	&error($err) if ($err);
	&webmin_log("pihole_restartdns");
	&redirect("pihole.cgi?mode=status");
	}
elsif ($in{'action'} eq 'gravity') {
	&ui_print_unbuffered_header(undef, $text{'pihole_gravitytitle'}, "");
	print $text{'pihole_gravityrun'},"<br>\n";
	my ($d, $err) = &pihole_api("POST", "/action/gravity");
	if ($err) {
		print "<b>",&text('pihole_gravityfailed', &html_escape($err)),
		      "</b><p>\n";
		}
	my $out = ref($d) ? "" : $d;
	# Strip terminal colour codes from the gravity script output
	$out =~ s/\e\[[0-9;]*[A-Za-z]//g;
	$out =~ s/\r//g;
	print "<pre>",&html_escape($out),"</pre>\n" if ($out =~ /\S/);
	print "<b>",$text{'pihole_gravitydone'},"</b><p>\n" if (!$err);
	&webmin_log("pihole_gravity");
	&ui_print_footer("pihole.cgi?mode=lists", $text{'pihole_return'});
	}
else {
	&error($text{'pihole_eaction'});
	}
