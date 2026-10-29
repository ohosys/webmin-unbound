#!/usr/local/bin/perl
# Make Pi-hole use Unbound : as its only upstream server, and for the local
# zones that Pi-hole would otherwise answer itself

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_err'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});
my $want = &unbound_upstream() || &error($text{'pihole_nolisten'});

my ($path, $old, $new);
if ($in{'do'} eq 'upstreams') {
	$path = "dns/upstreams";
	$old = &pihole_config($path) || [ ];
	$new = [ $want ];
	}
elsif ($in{'do'} eq 'zones') {
	$path = "dns/revServers";
	$old = &pihole_config($path) || [ ];
	$new = &pihole_fix_revservers($old);
	}
else {
	&error($text{'pihole_eaction'});
	}

if (!$in{'confirm'}) {
	&ui_print_header(undef, $text{'pihole_title'}, "");
	print &text('pihole_rusure_'.$in{'do'}, "<tt>".&html_escape($want).
						"</tt>"),"<p>\n";
	print &ui_columns_table([ $text{'pihole_before'}, $text{'pihole_after'} ],
		100, [ [ join("<br>", map { "<tt>".&html_escape($_)."</tt>" }
					  @$old) || "-",
			 join("<br>", map { "<tt>".&html_escape($_)."</tt>" }
					  @$new) ] ]);
	print &ui_confirmation_form("pihole_unbound.cgi", $text{'pihole_apply'},
		[ [ "do", $in{'do'} ], [ "confirm", 1 ] ],
		[ [ undef, $text{'pihole_applyok'} ] ]);
	&ui_print_footer("pihole.cgi?mode=unbound", $text{'pihole_return'});
	exit;
	}

my $err = &pihole_set_config($path, $new);
&error($err) if ($err);
&webmin_log("pihole_".$in{'do'}, undef, undef, { 'old' => join(" ", @$old),
						   'new' => join(" ", @$new) });
&redirect("pihole.cgi?mode=unbound");
