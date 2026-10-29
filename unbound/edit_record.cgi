#!/usr/local/bin/perl
# Show a form for adding or editing one local-data record

require './unbound-lib.pl';
&ReadParse();
&can_edit('local') || &error($text{'local_ecannot'});

my $zname = $in{'zone'} ne '' ? &canonical_name($in{'zone'}) : '.';
my ($r, $type);
if ($in{'new'}) {
	$type = uc($in{'type'});
	&indexof($type, @record_types) >= 0 || &error($text{'record_etype'});
	$r = { 'type' => $type, 'values' => [ ] };
	}
else {
	$r = &find_record_by_id($in{'id'}, $in{'old'}) ||
		&error($text{'record_egone'});
	$type = $r->{'type'};
	}

&ui_print_header($zname eq '.' ? undef : &html_escape(&display_name($zname)),
		 $in{'new'} ? $text{'record_create'} : $text{'record_edit'}, "");

print &ui_form_start("save_record.cgi", "post");
print &ui_hidden("zone", $in{'zone'});
print &ui_hidden("new", $in{'new'});
print &ui_hidden("type", $type);
print &ui_hidden("id", $in{'id'});
print &ui_hidden("old", $in{'old'});
print &ui_table_start(&text('record_header',
			    $text{'type_'.$type} || $type), "width=100%", 2);

my @v = @{$r->{'values'}};
if ($type eq 'REVPTR') {
	print &ui_table_row($text{'record_ip'},
		&ui_textbox("ip", $r->{'ip'}, 40));
	print &ui_table_row($text{'record_host'},
		&ui_textbox("name", $r->{'name'}, 40));
	}
else {
	my $show = $in{'new'} ? "" : &relative_record_name($r->{'name'}, $zname);
	print &ui_table_row($text{'record_name'},
		&ui_textbox("name", $show, 40).
		($zname ne '.' ? " <tt>.".&html_escape(&display_name($zname)).
				 "</tt>" : "").
		"<br><small>".$text{'record_namedesc'}."</small>");
	}
print &ui_table_row($text{'record_ttl'},
	&ui_opt_textbox("ttl", $r->{'ttl'}, 8, $text{'default'})." ".
	$text{'record_secs'});

if ($type eq 'A' || $type eq 'AAAA') {
	print &ui_table_row($text{'record_address'},
		&ui_textbox("value", $v[0], 40));
	if ($in{'new'}) {
		print &ui_table_row($text{'record_rev'},
			&ui_yesno_radio("rev", 0));
		}
	}
elsif ($type eq 'CNAME' || $type eq 'NS' || $type eq 'PTR') {
	print &ui_table_row($text{'record_target'},
		&ui_textbox("value", $v[0], 50));
	}
elsif ($type eq 'MX') {
	print &ui_table_row($text{'record_pref'},
		&ui_textbox("pref", $v[0] eq '' ? 10 : $v[0], 5));
	print &ui_table_row($text{'record_mx'},
		&ui_textbox("value", $v[1], 50));
	}
elsif ($type eq 'SRV') {
	print &ui_table_row($text{'record_prio'},
		&ui_textbox("prio", $v[0] eq '' ? 0 : $v[0], 5));
	print &ui_table_row($text{'record_weight'},
		&ui_textbox("weight", $v[1] eq '' ? 0 : $v[1], 5));
	print &ui_table_row($text{'record_port'},
		&ui_textbox("port", $v[2], 6));
	print &ui_table_row($text{'record_target'},
		&ui_textbox("value", $v[3], 50));
	}
elsif ($type eq 'TXT') {
	print &ui_table_row($text{'record_text'},
		&ui_textarea("value", &txt_unquote($r->{'data'}), 3, 60));
	}
elsif ($type eq 'CAA') {
	print &ui_table_row($text{'record_flags'},
		&ui_textbox("flags", $v[0] eq '' ? 0 : $v[0], 4));
	print &ui_table_row($text{'record_tag'},
		&ui_select("tag", $v[1] || "issue",
			   [ "issue", "issuewild", "iodef" ], 1, 0, 1));
	print &ui_table_row($text{'record_caavalue'},
		&ui_textbox("value", &txt_unquote(join(" ", @v[2..$#v])), 50));
	}

print &ui_table_end();
print &ui_form_end($in{'new'} ? [ [ "create", $text{'create'} ] ]
			      : [ [ "save", $text{'save'} ],
				  [ "delete", $text{'delete'} ] ]);

&ui_print_footer($zname eq '.' && $in{'zone'} eq ''
		   ? "edit_local.cgi?orphans=1"
		   : "edit_local.cgi?zone=".&urlize($zname),
		 $text{'local_return'});
