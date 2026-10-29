#!/usr/local/bin/perl
# Start the Unbound server

require './unbound-lib.pl';
&error_setup($text{'start_err'});
&can_edit('apply') || &error($text{'apply_ecannot'});
my $err = &start_unbound();
&error($err) if ($err);
&webmin_log("start");
&redirect("");
