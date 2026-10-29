# system_info.pl
# Status blocks for the Webmin dashboard

do 'unbound-lib.pl';

# list_system_info(&data, &in)
# Returns a warning if Unbound is down or misconfigured, and a table of
# statistics if it is running
sub list_system_info
{
my ($data, $in) = @_;
return ( ) if (!&foreign_available($module_name));
return ( ) if (!&has_command($config{'unbound'}) || !-r &get_config_file());
return ( ) if ($config{'dashboard'} eq '0');
my @rv;
my $link = &get_webprefix()."/$module_name/";
if (&can_edit('apply')) {
	my @errs = &check_config();
	if (@errs) {
		push(@rv, { 'type' => 'warning',
			    'level' => 'danger',
			    'id' => 'unbound_conf',
			    'warning' => &text('sysinfo_econf',
					&ui_link($link."check.cgi",
						 $text{'check_title'})) });
		}
	}
my $pid = &is_unbound_running();
if (!$pid) {
	push(@rv, { 'type' => 'warning',
		    'level' => 'warn',
		    'id' => 'unbound_down',
		    'warning' => &text('sysinfo_down',
				       &ui_link($link, $text{'index_title'})) });
	return @rv;
	}
if (&can_edit('control') && &control_available()) {
	my %st = &get_stats();
	my $q = $st{'total.num.queries'} || 0;
	my $hits = $st{'total.num.cachehits'} || 0;
	push(@rv, { 'type' => 'table',
		    'id' => 'unbound_stats',
		    'desc' => $text{'sysinfo_title'},
		    'open' => 0,
		    'table' => [
			{ 'desc' => $text{'stat_queries'}, 'value' => $q },
			{ 'desc' => $text{'stat_hits'},
			  'value' => $q ? sprintf("%.1f%%", 100*$hits/$q)
					: "-" },
			{ 'desc' => $text{'stat_rectime'},
			  'value' => $st{'total.recursion.time.avg'} ne ''
				? sprintf("%.3f s",
					  $st{'total.recursion.time.avg'})
				: "-" },
			{ 'desc' => $text{'stat_uptime'},
			  'value' => &nice_duration($st{'time.up'}) },
			] });
	}
# Pi-hole using this Unbound
if (&can_edit('pihole')) {
	&load_pihole_lib();
	if (&pihole_installed()) {
		my $sum = &pihole_get("/stats/summary");
		my $blk = &pihole_get("/dns/blocking");
		if ($sum && $blk) {
			my $q = $sum->{'queries'} || { };
			push(@rv, { 'type' => 'table',
				    'id' => 'unbound_pihole',
				    'desc' => $text{'sysinfo_pihole'},
				    'open' => 0,
				    'table' => [
				{ 'desc' => $text{'pihole_blocking'},
				  'value' => $blk->{'blocking'} eq 'enabled' ?
					$text{'pihole_benabled'} :
					$text{'pihole_bdisabled'} },
				{ 'desc' => $text{'pihole_qtotal'},
				  'value' => int($q->{'total'}) },
				{ 'desc' => $text{'pihole_qblocked'},
				  'value' => int($q->{'blocked'})." (".
				    sprintf("%.1f%%", $q->{'percent_blocked'}).")" },
				{ 'desc' => $text{'pihole_gravity'},
				  'value' => int($sum->{'gravity'}->{'domains_being_blocked'}) },
				] });
			}
		elsif (&pihole_ftl_running() == 0) {
			push(@rv, { 'type' => 'warning',
				    'level' => 'warn',
				    'id' => 'unbound_pihole_down',
				    'warning' => &text('sysinfo_piholedown',
					&ui_link($link."pihole.cgi",
						 $text{'pihole_title'})) });
			}
		}
	}
return @rv;
}

1;
