#!/usr/local/bin/perl
# Show a client view: which clients use it, and its own local zones and
# records

require './unbound-lib.pl';
&ReadParse();
&can_edit('views') || &error($text{'view_ecannot'});

my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause("view", $in{'name'}) ||
		&error($text{'view_egone'});
	}
my $vname = $c ? &find_clause_value("name", $c) : "";
&ui_print_header($c ? &html_escape($vname) : undef,
		 $c ? $text{'view_edit'} : $text{'view_create'}, "");

print $text{'view_desc'},"<p>\n";
print &ui_form_start("save_view.cgi", "post");
print &ui_hidden("new", $in{'new'});
print &ui_hidden("old", $in{'name'});
print &ui_table_start($text{'view_header'}, "width=100%", 2);
my $cc = $c || { 'members' => [ ] };
print &ui_table_row($text{'view_name'},
	&ui_textbox("name", $vname, 30));
my @clients = $c ? map { (split(/\s+/, join(" ", @{$_->{'values'}})))[0] }
		      &view_clients($vname) : ( );
print &ui_table_row($text{'view_clients'},
	&ui_textarea("clients", join("\n", @clients), 4, 40).
	"<br><small>".$text{'view_clientsdesc'}."</small>");
print &ui_table_row($text{'view_first'},
	&yesno_input("first", &find_clause_value("view-first", $cc)).
	"<br><small>".$text{'view_firstdesc'}."</small>");
print &ui_table_row($text{'view_zones'},
	&ui_textarea("zones", join("\n", map { join(" ", @{$_->{'values'}}) }
				      &find_dirs("local-zone", [ $cc ])), 4, 60).
	"<br><small>".$text{'view_zonesdesc'}."</small>");
print &ui_table_row($text{'view_data'},
	&ui_textarea("data", join("\n", &find_clause_values("local-data", $cc)),
		     6, 60).
	"<br><small>".$text{'view_datadesc'}."</small>");
if ($c) {
	print &ui_table_row($text{'local_file'},
		"<tt>".&html_escape($c->{'file'})."</tt>");
	}
print &ui_table_end();
print &ui_form_end($in{'new'} ? [ [ "create", $text{'create'} ] ]
			      : [ [ "save", $text{'save'} ],
				  [ "delete", $text{'delete'} ] ]);

&ui_print_footer("index.cgi?mode=views", $text{'index_return'});
