#!/usr/local/bin/perl
# Show the Unbound module main page: global option icons, zone lists and
# start / stop / apply buttons

require './unbound-lib.pl';
&ReadParse();

# Make sure Unbound is installed
if (!&has_command($config{'unbound'})) {
	&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1);
	print &text('index_ecmd', "<tt>".&html_escape($config{'unbound'}).
				  "</tt>", "../config.cgi?$module_name"),"<p>\n";
	&foreign_require("software", "software-lib.pl");
	my $lnk = &software::missing_install_link(
		"unbound", $text{'index_unbound'}, "../$module_name/",
		$text{'index_title'});
	print $lnk,"<p>\n" if ($lnk);
	&ui_print_footer("/", $text{'index'});
	exit;
	}

my $ver = &get_unbound_version();
&ui_print_header(undef, $text{'index_title'}, "", undef, 1, 1, 0,
	&help_search_link("unbound", "man", "doc", "google"),
	undef, undef, $ver ? &text('index_version', $ver) : undef);

# Make sure the config file exists
if (!-r &get_config_file()) {
	print &text('index_econf', "<tt>".&html_escape(&get_config_file()).
				   "</tt>", "../config.cgi?$module_name"),"<p>\n";
	&ui_print_footer("/", $text{'index'});
	exit;
	}

# Project header, state of Unbound and Pi-hole, and the main statistics
require './brand-lib.pl';
my $pid = &is_unbound_running();
my $lport = &find_server_value("port") || 53;
my @pills = ( $pid ? [ 'ok', &text('brand_urunning', $lport) ]
		   : [ 'off', $text{'brand_ustopped'} ] );
if (&can_edit('pihole') && &pihole_installed_quick()) {
	require './pihole-lib.pl';
	my $blk = &pihole_ftl_running() ? &pihole_get("/dns/blocking") : undef;
	push(@pills, !&pihole_ftl_running() ?
			[ 'off', $text{'brand_pstopped'} ] :
		     !$blk ? [ 'mid', $text{'brand_pnoapi'} ] :
		     $blk->{'blocking'} eq 'enabled' ?
			[ 'ok', $text{'brand_pblocking'} ] :
			[ 'mid', $text{'brand_pnoblocking'} ]);
	}
print &brand_header('unbound', \@pills);
if ($pid && &can_edit('control') && &control_available()) {
	my %st = &get_stats();
	my $q = $st{'total.num.queries'} || 0;
	my $hits = $st{'total.num.cachehits'} || 0;
	print &brand_tiles([
		[ 'u1', &brand_number($q), $text{'stat_queries'}, 'exchange' ],
		[ 'u2', $q ? &brand_pct(100*$hits/$q) : "-",
		  $text{'stat_hits'}, 'bolt' ],
		[ 'u3', $st{'total.recursion.time.avg'} ne '' ?
			sprintf("%.0f ms", 1000*$st{'total.recursion.time.avg'})
			: "-", $text{'stat_rectime'}, 'clock-o' ],
		[ 'u4', &nice_duration($st{'time.up'}), $text{'stat_uptime'},
		  'heartbeat' ],
		]);
	}

# Icons for global options
my @pages;
push(@pages, "net", "perf", "sec", "log") if (&can_edit('opts'));
push(@pages, "access") if (&can_edit('acl'));
push(@pages, "rc") if (&can_edit('opts'));
push(@pages, "control") if (&can_edit('control'));
push(@pages, "check") if (&can_edit('apply'));
push(@pages, "manual") if (&can_edit('manual'));
# Pi-hole has its own switch in the header, so no icon is needed for it
if (@pages) {
	my @links = map { $_ eq 'access' ? 'edit_access.cgi' :
			  $_ eq 'control' ? 'control.cgi' :
			  $_ eq 'check' ? 'check.cgi' :
			  $_ eq 'manual' ? 'edit_manual.cgi' :
			  $_ eq 'pihole' ? 'pihole.cgi' :
			  'edit_opts.cgi?page='.$_ } @pages;
	my @titles = map { $text{$_.'_title'} } @pages;
	my @icons = map { "images/$_.gif" } @pages;
	&icons_table(\@links, \@titles, \@icons, 5);
	print &ui_hr();
	}

# Tabs for the zone types
my @tabs;
push(@tabs, [ 'local', $text{'index_tlocal'} ]) if (&can_edit('local'));
push(@tabs, [ 'forward', $text{'index_tforward'} ]) if (&can_edit('forward'));
push(@tabs, [ 'stub', $text{'index_tstub'} ]) if (&can_edit('stub'));
push(@tabs, [ 'auth', $text{'index_tauth'} ]) if (&can_edit('auth'));
push(@tabs, [ 'rpz', $text{'index_trpz'} ]) if (&can_edit('rpz'));
push(@tabs, [ 'views', $text{'index_tviews'} ]) if (&can_edit('views'));
if (@tabs) {
	my $mode = $in{'mode'} || $tabs[0]->[0];
	print &ui_tabs_start(\@tabs, 'mode', $mode, 1);

	if (&can_edit('local')) {
		print &ui_tabs_start_tab('mode', 'local');
		&show_local_zones();
		print &ui_tabs_end_tab('mode', 'local');
		}
	foreach my $t ('forward', 'stub', 'auth', 'rpz', 'views') {
		next if (!&can_edit($t));
		print &ui_tabs_start_tab('mode', $t);
		&show_zone_clauses($t);
		print &ui_tabs_end_tab('mode', $t);
		}
	print &ui_tabs_end(1);
	}

# Start / stop / apply buttons
if (&can_edit('apply')) {
	print &ui_hr();
	print &ui_buttons_start();
	if (&is_unbound_running()) {
		print &ui_buttons_row("apply.cgi", $text{'index_apply'},
			&restart_needed() ? "<b>".$text{'index_restartneeded'}.
					    "</b>"
					  : $text{'index_applydesc'});
		print &ui_buttons_row("stop.cgi", $text{'index_stop'},
				      $text{'index_stopdesc'});
		}
	else {
		print &ui_buttons_row("start.cgi", $text{'index_start'},
				      $text{'index_startdesc'});
		}
	if ($config{'init_script'}) {
		&foreign_require("init");
		my $st = &init::action_status($config{'init_script'});
		if ($st) {
			print &ui_buttons_row("bootup.cgi",
				$text{'index_boot'}, $text{'index_bootdesc'},
				undef,
				&ui_yesno_radio("boot", $st == 2 ? 1 : 0));
			}
		}
	print &ui_buttons_end();
	}

&ui_print_footer("/", $text{'index'});

# show_local_zones()
# Prints the table of local zones
sub show_local_zones
{
my @zones = sort { &canonical_name($a->{'name'}) cmp
		   &canonical_name($b->{'name'}) } &list_local_zones();
my @recs = &list_local_records();
my %count;
foreach my $r (@recs) {
	my $z = &record_zone($r, \@zones);
	$count{defined($z) ? &canonical_name($z) : ""}++;
	}
print $text{'index_localdesc'},"<p>\n";
my @links = ( [ "edit_local.cgi?new=1", $text{'index_addlocal'} ],
	      [ "edit_batch.cgi", $text{'index_batch'} ] );
if ($count{""}) {
	push(@links, [ "edit_local.cgi?orphans=1",
		       &text('index_orphans', $count{""}) ]);
	}
my @rows;
foreach my $z (@zones) {
	my $n = &canonical_name($z->{'name'});
	push(@rows, [
		{ 'type' => 'checkbox', 'name' => 'd', 'value' => $n },
		"<a href='edit_local.cgi?zone=".&urlize($n)."'>".
		  &html_escape(&display_name($n))."</a>",
		&html_escape($z->{'type'}),
		$count{$n} || 0,
		]);
	}
print &ui_form_columns_table(
	"delete_zones.cgi",
	[ [ "delete", $text{'index_deletesel'} ] ],
	1,
	\@links,
	[ [ "type", "local" ] ],
	[ "", $text{'index_zname'}, $text{'index_ztype'},
	  $text{'index_zrecs'} ],
	100, \@rows, undef, 0, undef, $text{'index_nolocal'});
}

# show_zone_clauses(type)
# Prints a table of forward, stub, auth or RPZ zones, or views
sub show_zone_clauses
{
my ($t) = @_;
my $ctype = $t eq 'rpz' ? 'rpz' : $t eq 'views' ? 'view' : $t."-zone";
my @zones = sort { lc($a->{'name'}) cmp lc($b->{'name'}) }
		 &list_zone_clauses($ctype);
print $text{'index_'.$t.'desc'},"<p>\n";
my $cgi = $t eq 'auth' ? "edit_auth.cgi?" :
	  $t eq 'rpz' ? "edit_rpz.cgi?" :
	  $t eq 'views' ? "edit_view.cgi?" : "edit_fwd.cgi?type=$t&";
my @rows;
foreach my $z (@zones) {
	my $c = $z->{'clause'};
	my $id = $t eq 'views' ? $z->{'name'} : &canonical_name($z->{'name'});
	my $show = $t eq 'views' ? $z->{'name'} : &display_name($id);
	my @cols = ( { 'type' => 'checkbox', 'name' => 'd', 'value' => $id },
		     "<a href='${cgi}name=".&urlize($id)."'>".
		       &html_escape($show)."</a>" );
	if ($t eq 'views') {
		my @cl = map { (split(/\s+/, join(" ", @{$_->{'values'}})))[0] }
			     &view_clients($z->{'name'});
		push(@cols, &html_escape(join(", ", @cl)) || "-",
		     scalar(&find_dirs("local-zone", [ $c ])) + 
		     scalar(&find_dirs("local-data", [ $c ])));
		}
	elsif ($t eq 'auth' || $t eq 'rpz') {
		my @src = ( &find_clause_values("url", $c),
			    &find_clause_values("primary", $c),
			    &find_clause_values("master", $c) );
		my $zf = &find_clause_value("zonefile", $c);
		push(@src, &text('index_zonefile', $zf)) if ($zf && !@src);
		push(@cols, &html_escape(join(", ", @src)) || "-");
		push(@cols, &html_escape(&find_clause_value(
				"rpz-action-override", $c) || $text{'rpz_anone'}))
			if ($t eq 'rpz');
		}
	else {
		my @addrs = ( &find_clause_values($t."-addr", $c),
			      &find_clause_values($t."-host", $c) );
		my $tls = &find_clause_value($t."-tls-upstream", $c);
		push(@cols, &html_escape(join(", ", @addrs)) || "-",
		     $tls eq 'yes' ? $text{'yes'} : $text{'no'});
		}
	push(@rows, \@cols);
	}
my $addlink = $t eq 'auth' ? "edit_auth.cgi?new=1" :
	      $t eq 'rpz' ? "edit_rpz.cgi?new=1" :
	      $t eq 'views' ? "edit_view.cgi?new=1" : "edit_fwd.cgi?type=$t&new=1";
my @heads = ( "", $t eq 'views' ? $text{'view_name'} : $text{'index_zname'} );
push(@heads, $t eq 'views' ? ( $text{'view_clients'}, $text{'index_zrecs'} ) :
	     $t eq 'auth' ? ( $text{'index_zprimary'} ) :
	     $t eq 'rpz' ? ( $text{'index_zsource'}, $text{'rpz_action'} ) :
	     ( $text{'index_zservers'}, $text{'index_ztls'} ));
print &ui_form_columns_table(
	"delete_zones.cgi",
	[ [ "delete", $text{'index_deletesel'} ] ],
	1,
	[ [ $addlink, $text{'index_add'.$t} ] ],
	[ [ "type", $t ] ],
	\@heads, 100, \@rows, undef, 0, undef, $text{'index_no'.$t});
}
