#!/usr/local/bin/perl
# Show an RPZ (response policy zone) blocklist, or a form to add one

require './unbound-lib.pl';
&ReadParse();
&can_edit('rpz') || &error($text{'rpz_ecannot'});

my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause("rpz", $in{'name'}) || &error($text{'rpz_egone'});
	}
&ui_print_header($c ? &html_escape(&display_name(&canonical_name(
				&find_clause_value("name", $c)))) : undef,
		 $c ? $text{'rpz_edit'} : $text{'rpz_create'}, "");

print $text{'rpz_desc'},"<p>\n";
print &ui_form_start("save_rpz.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("old", $in{'name'});
print &ui_table_start($text{'rpz_header'}, "width=100%", 2);

my $cc = $c || { 'members' => [ ] };
print &ui_table_row($text{'rpz_name'},
	&ui_textbox("name", $c ? &find_clause_value("name", $c) : "", 40).
	"<br><small>".$text{'rpz_namedesc'}."</small>");
print &ui_table_row($text{'auth_urls'},
	&ui_textarea("urls", join("\n", &find_clause_values("url", $cc)),
		     2, 70)."<br><small>".$text{'rpz_urldesc'}."</small>");
print &ui_table_row($text{'auth_primaries'},
	&ui_textarea("primaries",
		join("\n", &find_clause_values("primary", $cc),
			   &find_clause_values("master", $cc)), 2, 40));
print &ui_table_row($text{'auth_zonefile'},
	&ui_opt_textbox("zonefile", &find_clause_value("zonefile", $cc), 50,
			$text{'auth_nofile'}).
	"<br><small>".$text{'rpz_zonefiledesc'}."</small>");
my $act = &find_clause_value("rpz-action-override", $cc);
print &ui_table_row($text{'rpz_action'},
	&ui_select("action", $act,
		[ [ "", $text{'rpz_anone'} ],
		  map { [ $_, $_." - ".$text{'rpz_a'.$_} ] }
		      ("nxdomain", "nodata", "passthru", "drop", "disabled",
		       "cname") ]));
print &ui_table_row($text{'rpz_cname'},
	&ui_opt_textbox("cname", &find_clause_value("rpz-cname-override", $cc),
			40, $text{'rpz_nocname'}));
print &ui_table_row($text{'rpz_log'},
	&yesno_input("log", &find_clause_value("rpz-log", $cc)));
print &ui_table_row($text{'rpz_logname'},
	&ui_opt_textbox("logname", &find_clause_value("rpz-log-name", $cc), 20,
			$text{'rpz_lognamedef'}));
print &ui_table_row($text{'rpz_ra'},
	&yesno_input("ra", &find_clause_value("rpz-signal-nxdomain-ra", $cc)));
if ($c) {
	print &ui_table_row($text{'local_file'},
		"<tt>".&html_escape($c->{'file'})."</tt>");
	}
print &ui_table_end();
print &ui_form_end($in{'new'} ? [ [ "create", $text{'create'} ] ]
			      : [ [ "save", $text{'save'} ],
				  [ "delete", $text{'delete'} ] ]);

&ui_print_footer("index.cgi?mode=rpz", $text{'index_return'});
