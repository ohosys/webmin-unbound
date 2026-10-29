#!/usr/local/bin/perl
# Show a local zone (its type and records), or a form to create one

require './unbound-lib.pl';
&ReadParse();
&can_edit('local') || &error($text{'local_ecannot'});

my ($zone, $zname);
if ($in{'new'}) {
	&ui_print_header(undef, $text{'local_create'}, "");
	}
elsif ($in{'orphans'}) {
	&ui_print_header(undef, $text{'local_orphans'}, "");
	}
else {
	$zone = &find_local_zone($in{'zone'}) ||
		&error($text{'local_egone'});
	$zname = &canonical_name($zone->{'name'});
	&ui_print_header(&html_escape(&display_name($zname)),
			 $text{'local_edit'}, "");
	}

if (!$in{'orphans'}) {
	# Zone name and type
	print &ui_form_start("save_local.cgi", "post");
	print &ui_hidden("new", $in{'new'});
	print &ui_hidden("old", $zname) if ($zone);
	print &ui_table_start($text{'local_header'}, "width=100%", 2);
	print &ui_table_row($text{'local_name'},
		$zone ? "<tt>".&html_escape(&display_name($zname))."</tt>"
		      : &ui_textbox("name", undef, 40));
	print &ui_table_row($text{'local_type'},
		&zone_types_select("type", $zone ? $zone->{'type'} : 'static').
		"<br><small>".$text{'local_typedesc'}."</small>");
	if ($zone) {
		print &ui_table_row($text{'local_file'},
			"<tt>".&html_escape($zone->{'dir'}->{'file'})."</tt>");
		}
	print &ui_table_end();
	print &ui_form_end($zone ?
		[ [ "save", $text{'save'} ],
		  [ "delete", $text{'local_delete'} ] ] :
		[ [ "create", $text{'create'} ] ]);
	}

if ($zone || $in{'orphans'}) {
	# Records table
	my @recs = &records_for_zone($zone ? $zname : undef);
	@recs = sort { &canonical_name($a->{'name'}) cmp
		       &canonical_name($b->{'name'}) ||
		       $a->{'type'} cmp $b->{'type'} } @recs;
	print &ui_hr() if ($zone);
	print &ui_subheading($text{'local_records'});
	my @rows;
	foreach my $r (@recs) {
		my $id = &record_id($r);
		my $show = $zone ? &relative_record_name($r->{'name'}, $zname)
				 : $r->{'name'};
		my $data = $r->{'type'} eq 'TXT' ? &txt_unquote($r->{'data'})
						 : $r->{'data'};
		push(@rows, [
			{ 'type' => 'checkbox', 'name' => 'd',
			  'value' => $id."\t".$r->{'dir'}->{'value'} },
			"<a href='edit_record.cgi?zone=".&urlize($zname).
			  "&id=".&urlize($id)."&old=".
			  &urlize($r->{'dir'}->{'value'})."'>".
			  &html_escape($show)."</a>",
			$text{'type_'.$r->{'type'}} || &html_escape($r->{'type'}),
			$r->{'ttl'} eq '' ? $text{'default'} : $r->{'ttl'},
			&html_escape($data),
			]);
		}
	my @links;
	if ($zone) {
		foreach my $t (@record_types) {
			push(@links, [ "edit_record.cgi?zone=".&urlize($zname).
				   "&type=$t&new=1", &text('local_add', $t) ]);
			}
		}
	print &ui_form_columns_table(
		"delete_records.cgi",
		[ [ "delete", $text{'local_deletesel'} ] ],
		1,
		\@links,
		[ [ "zone", $zname ], [ "orphans", $in{'orphans'} ] ],
		[ "", $text{'record_name'}, $text{'record_type'},
		  $text{'record_ttl'}, $text{'record_value'} ],
		100, \@rows, undef, 0, undef, $text{'local_norecs'});
	}

&ui_print_footer("index.cgi?mode=local", $text{'index_return'});
