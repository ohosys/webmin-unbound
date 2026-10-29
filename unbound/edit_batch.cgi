#!/usr/local/bin/perl
# Show a form for importing many local records at once, from text in hosts
# or record format, /etc/hosts, or DHCP leases

require './unbound-lib.pl';
&ReadParse();
&can_edit('local') || &error($text{'local_ecannot'});
&ui_print_header(undef, $text{'batch_title'}, "");

my @zones = sort { $a cmp $b }
		 map { &canonical_name($_->{'name'}) } &list_local_zones();
if (!@zones) {
	print $text{'batch_nozones'},"<p>\n";
	&ui_print_footer("index.cgi?mode=local", $text{'index_return'});
	exit;
	}
my @leases = &list_dhcp_leases();
my $hosts = scalar(&parse_hosts_lines(&read_file_contents("/etc/hosts")));

print $text{'batch_desc'},"<p>\n";
print &ui_form_start("save_batch.cgi", "post");
print &ui_table_start($text{'batch_header'}, "width=100%", 2);
print &ui_table_row($text{'batch_zone'},
	&ui_select("zone", $in{'zone'} ? &canonical_name($in{'zone'})
				       : $zones[0],
		   [ map { [ $_, &display_name($_) ] } @zones ]).
	"<br><small>".$text{'batch_zonedesc'}."</small>");
print &ui_table_row($text{'batch_source'},
	&ui_radio_table("source", "text", [
		[ "text", $text{'batch_stext'},
		  &ui_radio("format", "hosts",
			    [ [ "hosts", $text{'batch_fhosts'} ],
			      [ "rr", $text{'batch_frr'} ] ])."<br>".
		  &ui_textarea("text", undef, 10, 70)."<br><small>".
		  $text{'batch_textdesc'}."</small>" ],
		[ "hosts", &text('batch_shosts', $hosts) ],
		@leases ? ( [ "leases", &text('batch_sleases',
						scalar(@leases)) ] )
			: ( [ "leases", $text{'batch_noleases'}, undef, 1 ] ),
		]));
print &ui_table_row($text{'batch_ptr'},
	&ui_yesno_radio("ptr", 0));
print &ui_table_row($text{'batch_dup'},
	&ui_radio("dup", "skip", [ [ "skip", $text{'batch_dupskip'} ],
				   [ "replace", $text{'batch_dupreplace'} ] ]));
print &ui_table_row($text{'record_ttl'},
	&ui_opt_textbox("ttl", undef, 8, $text{'default'})." ".
	$text{'record_secs'});
print &ui_table_end();
print &ui_form_end([ [ "preview", $text{'batch_preview'} ],
		     [ "import", $text{'batch_import'} ] ]);

&ui_print_footer("index.cgi?mode=local", $text{'index_return'});
