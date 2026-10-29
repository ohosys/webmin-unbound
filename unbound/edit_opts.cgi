#!/usr/local/bin/perl
# Show a page of global options (network, performance, security, logging,
# remote control). The options on each page are defined in option_pages().

require './unbound-lib.pl';
&ReadParse();
&can_edit('opts') || &error($text{'opts_ecannot'});
my %pages = &option_pages();
my $page = $pages{$in{'page'}} || &error($text{'opts_epage'});
my ($cname, @opts) = @$page;

&ui_print_header(undef, $text{$in{'page'}.'_title'}, "");

my @clauses = &find_clauses($cname);
print $text{$in{'page'}.'_desc'},"<p>\n" if ($text{$in{'page'}.'_desc'});

print &ui_form_start("save_opts.cgi", "post");
print &ui_hidden("page", $in{'page'});
print &ui_table_start($text{$in{'page'}.'_header'}, "width=100%", 2);

my $i = 0;
foreach my $o (@opts) {
	my ($name, $type, $extra) = @$o;
	my @dirs = &find_dirs($name, \@clauses);
	my @vals = map { $_->{'values'}->[0] } @dirs;
	my $cur = @vals ? $vals[$#vals] : undef;
	my $label = ($text{'opt_'.$name} || $name).
		    "<br><small><tt>$name</tt></small>";
	my $def = &default_label($name);
	my $field;
	if ($type eq 'yesno') {
		$field = &yesno_input("o_$i", $cur, $def);
		}
	elsif ($type eq 'select') {
		$field = &ui_select("o_$i", $cur,
			[ [ '', $def ], map { [ $_, $_ ] } @$extra ]);
		}
	elsif ($type eq 'multi') {
		$field = &ui_textarea("o_$i", join("\n", @vals), 4, 40)."<br>".
			 "<small>".$text{'opts_multi'}.
			 (@vals ? "" : " ".$def)."</small>";
		}
	else {
		my $size = $type eq 'file' || $type eq 'text' ? 50 : 10;
		$field = &ui_opt_textbox("o_$i", $cur, $size, $def);
		}
	print &ui_table_row($label, $field);
	$i++;
	}

print &ui_table_end();
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
