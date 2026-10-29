#!/usr/local/bin/perl
# Save the access control list

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'access_err'});
&can_edit('acl') || &error($text{'access_ecannot'});

my @vals;
for(my $i=0; defined($in{"net_$i"}); $i++) {
	my $net = $in{"net_$i"};
	$net =~ s/^\s+|\s+$//g;
	next if ($net eq '');
	&valid_netblock($net) ||
		&error(&text('access_enet', &html_escape($net)));
	my $act = $in{"action_$i"};
	&indexof($act, @access_actions) >= 0 ||
		&error(&text('access_eaction', &html_escape($act)));
	push(@vals, $net." ".$act);
	}

&begin_change();
&save_server("access-control", \@vals);
&commit_change();
&webmin_log("access");
&redirect("");
