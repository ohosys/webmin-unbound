# status_monitor.pl
# Monitor types for the System and Server Status module

do 'unbound-lib.pl';

# status_monitor_list()
# Returns the monitor types this module provides
sub status_monitor_list
{
my @rv = ( [ "up", $text{'monitor_up'} ],
	   [ "query", $text{'monitor_query'} ] );
&load_pihole_lib();
push(@rv, [ "pihole", $text{'monitor_pihole'} ]) if (&pihole_installed());
return @rv;
}

# status_monitor_status(type, &monitor, from-ui)
# Checks if Unbound is running, or if it answers a query correctly
sub status_monitor_status
{
my ($type, $mon, $fromui) = @_;
if ($type eq "pihole") {
	# Pi-hole running and answering on port 53
	&load_pihole_lib();
	return { 'up' => -1, 'desc' => $text{'pihole_enot'} }
		if (!&pihole_installed());
	my $pid = &pihole_ftl_running();
	return { 'up' => 0, 'desc' => $text{'monitor_piholedown'} } if (!$pid);
	return { 'up' => 1, 'desc' => &text('monitor_pid', $pid) }
		if (!&has_command("dig"));
	my $out = &backquote_command("dig +time=3 +tries=1 \@127.0.0.1 -p 53 ".
				     "pi.hole A 2>&1 </dev/null");
	return { 'up' => 0, 'desc' => $text{'monitor_piholenoanswer'} }
		if ($out !~ /status:\s*NOERROR/);
	return { 'up' => 1, 'desc' => &text('monitor_pid', $pid) };
	}
if (!&has_command($config{'unbound'})) {
	return { 'up' => -1, 'desc' => $text{'monitor_noprog'} };
	}
if ($type eq "up") {
	my $pid = &is_unbound_running();
	return { 'up' => 0, 'desc' => $text{'monitor_down'} } if (!$pid);
	if ($mon->{'control'}) {
		my ($ok, $out) = &control_command("status");
		return { 'up' => 0, 'desc' => $text{'monitor_nocontrol'} }
			if (!$ok);
		}
	return { 'up' => 1, 'desc' => &text('monitor_pid', $pid) };
	}
elsif ($type eq "query") {
	my ($ok, $answers, $err) = &test_query($mon->{'host'} || "127.0.0.1",
					       $mon->{'name'},
					       $mon->{'qtype'} || "A");
	return { 'up' => 0, 'desc' => $err } if (!$ok);
	if ($mon->{'expect'} ne '' &&
	    &indexof($mon->{'expect'}, @$answers) < 0) {
		return { 'up' => 0,
			 'desc' => &text('monitor_wrong',
					 join(" ", @$answers) || "-") };
		}
	return { 'up' => 1, 'desc' => join(" ", @$answers) };
	}
return { 'up' => -1, 'desc' => $text{'monitor_notype'} };
}

# status_monitor_dialog(type, &monitor)
# Returns form fields for a monitor
sub status_monitor_dialog
{
my ($type, $mon) = @_;
return undef if ($type eq "pihole");
if ($type eq "up") {
	return &ui_table_row($text{'monitor_control'},
		&ui_yesno_radio("control", $mon->{'control'} ? 1 : 0));
	}
my $rv = &ui_table_row($text{'monitor_name'},
		&ui_textbox("name", $mon->{'name'} || "localhost", 40));
$rv .= &ui_table_row($text{'monitor_qtype'},
		&ui_select("qtype", $mon->{'qtype'} || "A",
			   [ "A", "AAAA", "MX", "TXT", "NS", "PTR" ]));
$rv .= &ui_table_row($text{'monitor_host'},
		&ui_textbox("host", $mon->{'host'} || "127.0.0.1", 30));
$rv .= &ui_table_row($text{'monitor_expect'},
		&ui_opt_textbox("expect", $mon->{'expect'}, 30,
				$text{'monitor_anyanswer'}));
return $rv;
}

# status_monitor_parse(type, &monitor, &in)
# Saves the form fields for a monitor
sub status_monitor_parse
{
my ($type, $mon, $in) = @_;
return if ($type eq "pihole");
if ($type eq "up") {
	$mon->{'control'} = $in->{'control'} ? 1 : 0;
	return;
	}
&valid_domain($in->{'name'}) || &error($text{'monitor_ename'});
$in->{'qtype'} =~ /^[A-Z]{1,6}$/ || &error($text{'control_eqtype'});
&valid_ip($in->{'host'}) || &error($text{'monitor_ehost'});
$mon->{'name'} = $in->{'name'};
$mon->{'qtype'} = $in->{'qtype'};
$mon->{'host'} = $in->{'host'};
if ($in->{'expect_def'}) {
	delete($mon->{'expect'});
	}
else {
	$in->{'expect'} =~ /^\S+$/ || &error($text{'monitor_eexpect'});
	$mon->{'expect'} = $in->{'expect'};
	}
}

1;
