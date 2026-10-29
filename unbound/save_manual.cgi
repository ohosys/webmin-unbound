#!/usr/local/bin/perl
# Save a manually edited config file, rolling back if it breaks the config

require './unbound-lib.pl';
&ReadParseMime();
&error_setup($text{'manual_err'});
&can_edit('manual') || &error($text{'manual_ecannot'});

my @files = grep { -e $_ } &get_config_files();
&indexof($in{'file'}, @files) >= 0 || &error($text{'manual_efile'});
$in{'data'} =~ s/\r//g;
$in{'data'} .= "\n" if ($in{'data'} ne '' && $in{'data'} !~ /\n$/);

&begin_change();
&open_tempfile(DATA, ">$in{'file'}");
&print_tempfile(DATA, $in{'data'});
&close_tempfile(DATA);
delete($main::file_cache{$in{'file'}});
&commit_change();

&webmin_log("manual", undef, $in{'file'});
&redirect("");
