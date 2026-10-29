#!/usr/local/bin/perl
# Show an auth-zone (a zone Unbound loads from a file, a primary server or
# a URL), or a form to create one

require './unbound-lib.pl';
&ReadParse();
&can_edit('auth') || &error($text{'auth_ecannot'});

my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause("auth-zone", $in{'name'}) ||
		&error($text{'auth_egone'});
	}
&ui_print_header($c ? &html_escape(&display_name(&canonical_name(
				&find_clause_value("name", $c)))) : undef,
		 $c ? $text{'auth_edit'} : $text{'auth_create'}, "");

print $text{'auth_desc'},"<p>\n";
print &ui_form_start("save_auth.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("old", $in{'name'});
print &ui_table_start($text{'auth_header'}, "width=100%", 2);

my $empty = { 'members' => [ ] };
my $cc = $c || $empty;
print &ui_table_row($text{'fwd_name'},
	&ui_textbox("name", $c ? &find_clause_value("name", $c) : "", 40));
print &ui_table_row($text{'auth_primaries'},
	&ui_textarea("primaries",
		join("\n", &find_clause_values("primary", $cc),
			   &find_clause_values("master", $cc)), 4, 40).
	"<br><small>".$text{'auth_primariesdesc'}."</small>");
print &ui_table_row($text{'auth_urls'},
	&ui_textarea("urls", join("\n", &find_clause_values("url", $cc)),
		     2, 60));
print &ui_table_row($text{'auth_notify'},
	&ui_textarea("notify",
		     join("\n", &find_clause_values("allow-notify", $cc)),
		     2, 40));
print &ui_table_row($text{'auth_zonefile'},
	&ui_opt_textbox("zonefile", &find_clause_value("zonefile", $cc), 50,
			$text{'auth_nofile'}).
	"<br><small>".$text{'auth_zonefiledesc'}."</small>");
print &ui_table_row($text{'auth_downstream'},
	&yesno_input("downstream", &find_clause_value("for-downstream", $cc)));
print &ui_table_row($text{'auth_upstream'},
	&yesno_input("upstream", &find_clause_value("for-upstream", $cc)));
print &ui_table_row($text{'auth_fallback'},
	&yesno_input("fallback", &find_clause_value("fallback-enabled", $cc)));
if ($c) {
	print &ui_table_row($text{'local_file'},
		"<tt>".&html_escape($c->{'file'})."</tt>");
	}

print &ui_table_end();
print &ui_form_end($in{'new'} ? [ [ "create", $text{'create'} ] ]
			      : [ [ "save", $text{'save'} ],
				  [ "delete", $text{'delete'} ] ]);

# Show the zone file contents, read-only
my $zf = $c ? &find_clause_value("zonefile", $c) : undef;
if ($zf && -r $zf) {
	print &ui_hr();
	print &ui_subheading(&text('auth_contents', "<tt>".
				   &html_escape($zf)."</tt>"));
	my $data = &read_file_contents($zf);
	if (length($data) > 100000) {
		$data = substr($data, 0, 100000)."\n...";
		}
	print "<pre>",&html_escape($data),"</pre>\n";
	}

&ui_print_footer("index.cgi?mode=auth", $text{'index_return'});
