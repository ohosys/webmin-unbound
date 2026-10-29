#!/usr/local/bin/perl
# Show the access control list (access-control: directives)

require './unbound-lib.pl';
&can_edit('acl') || &error($text{'access_ecannot'});
&ui_print_header(undef, $text{'access_title'}, "");

print $text{'access_desc'},"<p>\n";

my @acls = map { $_->{'values'} } &find_server("access-control");
my @actions = map { [ $_, $_." - ".($text{'action_'.$_} || $_) ] }
		  @access_actions;

print &ui_form_start("save_access.cgi", "post");
print &ui_columns_start([ $text{'access_net'}, $text{'access_action'} ]);
my $i = 0;
foreach my $a (@acls, [ ], [ ], [ ]) {
	print &ui_columns_row([
		&ui_textbox("net_$i", $a->[0], 30),
		&ui_select("action_$i", $a->[1] || "allow", \@actions, 1, 0,
			   1),
		]);
	$i++;
	}
print &ui_columns_end();
print "<small>",$text{'access_note'},"</small><p>\n";
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
