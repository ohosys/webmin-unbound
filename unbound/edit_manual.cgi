#!/usr/local/bin/perl
# Show a page for manually editing one of the Unbound config files

require './unbound-lib.pl';
&ReadParse();
&can_edit('manual') || &error($text{'manual_ecannot'});
&ui_print_header(undef, $text{'manual_title'}, "");

my @files = grep { -e $_ } &get_config_files();
my $file = $in{'file'} || $files[0];
&indexof($file, @files) >= 0 || &error($text{'manual_efile'});

# File selector
print &ui_form_start("edit_manual.cgi");
print "<b>$text{'manual_file'}</b>\n";
print &ui_select("file", $file, \@files),"\n";
print &ui_submit($text{'manual_ok'});
print &ui_form_end();

# File contents
print &ui_form_start("save_manual.cgi", "form-data");
print &ui_hidden("file", $file);
print &ui_table_start(undef, undef, 2);
print &ui_table_row(undef,
	&ui_textarea("data", &read_file_contents($file), 25, 90), 2);
print &ui_table_end();
print "<small>",$text{'manual_note'},"</small><p>\n";
print &ui_form_end([ [ "save", $text{'save'} ] ]);

&ui_print_footer("", $text{'index_return'});
