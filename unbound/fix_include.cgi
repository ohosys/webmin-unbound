#!/usr/local/bin/perl
# Make Unbound read the .conf files of a directory it currently ignores, by
# adding an include: line to the main config file

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'fixinc_err'});
&can_edit('manual') || &error($text{'check_ecannot'});

# Only the usual directories next to the main config file
my $main = &get_config_file();
(my $base = $main) =~ s/\/[^\/]+$//;
my $dir = $in{'dir'};
&indexof($dir, map { "$base/$_" } ("unbound.conf.d", "conf.d", "local.d")) >= 0
	&& -d $dir || &error($text{'fixinc_edir'});
&indexof($dir, &included_conf_dirs()) < 0 || &error($text{'fixinc_ealready'});

if (!$in{'confirm'}) {
	&ui_print_header(undef, $text{'fixinc_title'}, "");
	print &ui_confirmation_form("fix_include.cgi",
		&text('fixinc_rusure', "<tt>".&html_escape("$dir/*.conf")."</tt>",
		      "<tt>".&html_escape($main)."</tt>"),
		[ [ "dir", $dir ], [ "confirm", 1 ] ],
		[ [ undef, $text{'fixinc_ok'} ] ]);
	&ui_print_footer("check.cgi", $text{'check_title'});
	exit;
	}

# Add the line, and take it out again if the result is not valid
my $old = &read_file_contents($main);
&include_conf_dir($dir);
my @errs = &check_config();
if (@errs) {
	&lock_file($main);
	&open_tempfile(MAIN, ">$main");
	&print_tempfile(MAIN, $old);
	&close_tempfile(MAIN);
	&unlock_file($main);
	&error(&text('fixinc_echeck', "<pre>".&html_escape(join("\n", @errs)).
				      "</pre>"));
	}
&webmin_log("include", undef, $dir);
&redirect("check.cgi");
