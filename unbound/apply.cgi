#!/usr/local/bin/perl
# Check the configuration, then make the running server load it

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'apply_err'});
&can_edit('apply') || &error($text{'apply_ecannot'});

# Don't silently cut off a forwarder like Pi-hole that depends on Unbound
my @probs = &forwarder_problems();
if (@probs && !$in{'confirm'}) {
	&ui_print_header(undef, $text{'apply_title'}, "");
	print "<b>",$text{'fwd_warn'},"</b><p>\n";
	print "<ul>",join("", map { "<li>$_</li>\n" } @probs),"</ul>\n";
	print &ui_confirmation_form("apply.cgi", $text{'fwd_rusure'},
				    [ [ "confirm", 1 ] ],
				    [ [ undef, $text{'fwd_anyway'} ] ]);
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

my $err = &apply_configuration();
&error($err) if ($err);
&webmin_log("apply");
&redirect("");
