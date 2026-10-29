#!/usr/local/bin/perl
# Stop the Unbound server

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'stop_err'});
&can_edit('apply') || &error($text{'apply_ecannot'});

# Stopping Unbound also stops DNS for everyone using Pi-hole on top of it
my $fw = &dns_forwarder();
if ($fw && @{$fw->{'to_unbound'}} && !$in{'confirm'}) {
	&ui_print_header(undef, $text{'stop_title'}, "");
	print &text('stop_rusurefwd', $fw->{'name'},
		    join(", ", map { "<tt>".&html_escape($_)."</tt>" }
				   @{$fw->{'to_unbound'}})),"<p>\n";
	print &ui_confirmation_form("stop.cgi", $text{'stop_rusure2'},
				    [ [ "confirm", 1 ] ],
				    [ [ undef, $text{'stop_ok'} ] ]);
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

my $err = &stop_unbound();
&error($err) if ($err);
&webmin_log("stop");
&redirect("");
