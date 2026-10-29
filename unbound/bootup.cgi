#!/usr/local/bin/perl
# Enable or disable Unbound at boot time

require './unbound-lib.pl';
&ReadParse();
&can_edit('apply') || &error($text{'apply_ecannot'});
# Only act on an explicit choice, so a stray link can't turn off boot start
$in{'boot'} =~ /^[01]$/ || &error($text{'bootup_echoice'});
&foreign_require("init");
if ($in{'boot'}) {
	&init::enable_at_boot($config{'init_script'}, "Unbound DNS server",
		quotemeta($config{'unbound'})." -c ".
		quotemeta(&get_config_file()),
		"kill `cat ".quotemeta(&get_pid_file())."`");
	}
else {
	&init::disable_at_boot($config{'init_script'});
	}
&webmin_log($in{'boot'} ? "bootup" : "bootdown");
&redirect("");
