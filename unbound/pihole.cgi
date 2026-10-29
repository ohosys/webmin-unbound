#!/usr/local/bin/perl
# Pi-hole pages : status and blocking, link to Unbound, allow and deny
# domains, blocklists, query log, clients and network

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&can_edit('pihole') || &error($text{'pihole_ecannot'});
&pihole_installed() || &error($text{'pihole_enot'});

my $info = &pihole_get("/info/version");
my $ftlver = $info ? $info->{'version'}->{'ftl'}->{'local'}->{'version'} : "";
&ui_print_header(undef, $text{'pihole_title'}, "", undef, 0, 0, 0, undef,
		 undef, undef, $ftlver ? &text('pihole_version', $ftlver)
				       : undef);

if (!$info) {
	# Can't talk to the API, so explain why
	print "<b>",&text('pihole_eapi', &html_escape($pihole_last_error)),
	      "</b><p>\n";
	my ($h, $p, $s) = &pihole_api_target();
	print &text('pihole_eapidesc', ($s ? "https" : "http")."://$h:$p/api",
		    &pihole_ftl_running() ? $text{'yes'} : $text{'no'},
		    "../config.cgi?$module_name"),"<p>\n";
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

require './brand-lib.pl';
my $blk = &pihole_get("/dns/blocking") || { };
my $upid = &is_unbound_running();
print &brand_header('pihole', [
	$blk->{'blocking'} eq 'enabled' ? [ 'ok', $text{'brand_pblocking'} ] :
					  [ 'mid', $text{'brand_pnoblocking'} ],
	[ undef, "<img src='images/pihole-logo.svg' alt=''>".
		 &html_escape("FTL $ftlver") ],
	$upid ? [ 'ok', &text('brand_urunning',
			      &find_server_value("port") || 53) ]
	      : [ 'off', $text{'brand_ustopped'} ],
	]);

my $mode = $in{'mode'} || 'status';
my @tabs = map { [ $_, $text{'pihole_t'.$_}, "pihole.cgi?mode=$_" ] }
	       ( 'status', 'unbound', 'domains', 'lists', 'queries', 'clients',
		 'network' );
print &ui_tabs_start(\@tabs, 'mode', $mode, 1);

# Colours for good / bad states
sub good { "<font color=green>$_[0]</font>" }
sub bad { "<font color=red><b>$_[0]</b></font>" }
sub warnc { "<font color=orange><b>$_[0]</b></font>" }

######################################################################
# Status and control
print &ui_tabs_start_tab('mode', 'status');
my $sum = &pihole_get("/stats/summary") || { };
my $q = $sum->{'queries'} || { };
my $grav = $sum->{'gravity'} || { };

print &brand_tiles([
	[ 'c1', &brand_number($q->{'total'}), $text{'pihole_qtotal'}, 'globe' ],
	[ 'c2', &brand_number($q->{'blocked'}), $text{'pihole_qblocked'},
	  'ban' ],
	[ 'c3', &brand_pct($q->{'percent_blocked'}),
	  $text{'pihole_pblocked'}, 'pie-chart' ],
	[ 'c4', &brand_number($grav->{'domains_being_blocked'}),
	  $text{'pihole_gravity'}, 'list' ],
	]);
print &ui_form_start("pihole_blocking.cgi", "post");
print &ui_table_start($text{'pihole_status'}, "width=100%", 4);
print &ui_table_row($text{'pihole_blocking'},
	$blk->{'blocking'} eq 'enabled' ? &good($text{'pihole_benabled'}) :
	$blk->{'blocking'} eq 'disabled' ?
		&bad($text{'pihole_bdisabled'}).
		($blk->{'timer'} ? " ".&text('pihole_btimer',
					     int($blk->{'timer'})) : "") :
		&html_escape($blk->{'blocking'} || "?"));
print &ui_table_row($text{'pihole_ftl'},
	&pihole_ftl_running() ? &good($text{'pihole_running'})
			      : &bad($text{'pihole_stopped'}));
print &ui_table_row($text{'pihole_qforwarded'}, int($q->{'forwarded'}));
print &ui_table_row($text{'pihole_qcached'}, int($q->{'cached'}));
print &ui_table_row($text{'pihole_gravityupd'},
	&pihole_time($grav->{'last_update'}));
print &ui_table_row($text{'pihole_clientsactive'},
	int($sum->{'clients'}->{'active'})." / ".
	int($sum->{'clients'}->{'total'}));
print &ui_table_row($text{'pihole_udomains'}, int($q->{'unique_domains'}));
print &ui_table_end();
if ($blk->{'blocking'} eq 'enabled') {
	print &ui_submit($text{'pihole_disable'}, "disable")," ",
	      &ui_select("timer", 0,
			 [ [ 0, $text{'pihole_tforever'} ],
			   [ 30, $text{'pihole_t30s'} ],
			   [ 300, $text{'pihole_t5m'} ],
			   [ 3600, $text{'pihole_t1h'} ] ]);
	}
else {
	print &ui_submit($text{'pihole_enable'}, "enable");
	}
print &ui_form_end();

print &ui_buttons_start();
print &ui_buttons_row("pihole_action.cgi", $text{'pihole_gravitynow'},
		      $text{'pihole_gravitydesc'},
		      [ [ "action", "gravity" ] ]);
print &ui_buttons_row("pihole_action.cgi", $text{'pihole_restartdns'},
		      $text{'pihole_restartdnsdesc'},
		      [ [ "action", "restartdns" ] ]);
print &ui_buttons_end();

# Top lists side by side
my $tb = &pihole_get("/stats/top_domains?blocked=true&count=10") || { };
my $tp = &pihole_get("/stats/top_domains?count=10") || { };
my $tc = &pihole_get("/stats/top_clients?count=10") || { };
my $up = &pihole_get("/stats/upstreams") || { };
my @grid;
# Each list gets a bar showing the share of all queries, like Pi-hole does
my $tot = $q->{'total'} || 1;
my $bars = sub {
	my ($title, $col, @rows) = @_;
	return &ui_columns_table([ $title, $text{'pihole_hits'}, "" ], 100,
		[ map { [ $_->[0], int($_->[1]), &brand_bar($_->[1], $tot, $col) ] }
		      @rows ], undef, 0, undef,
		$text{'pihole_none'});
	};
push(@grid, $bars->($text{'pihole_topblocked'}, "#dd4b39",
	map { [ &html_escape($_->{'domain'}), $_->{'count'} ] }
	    @{$tb->{'domains'} || [ ]}));
push(@grid, $bars->($text{'pihole_toppermitted'}, "#00a65a",
	map { [ &html_escape($_->{'domain'}), $_->{'count'} ] }
	    @{$tp->{'domains'} || [ ]}));
push(@grid, $bars->($text{'pihole_topclients'}, "#3164b4",
	map { [ &html_escape($_->{'name'} ? "$_->{'name'} ($_->{'ip'})"
					  : $_->{'ip'}), $_->{'count'} ] }
	    @{$tc->{'clients'} || [ ]}));
push(@grid, $bars->($text{'pihole_upstream'}, "#f39c12",
	map { [ &html_escape($_->{'port'} > 0 ? "$_->{'ip'}#$_->{'port'}"
					      : $_->{'name'}),
		$_->{'count'} ] } @{$up->{'upstreams'} || [ ]}));
print &ui_grid_table(\@grid, 2, 100);
print &ui_tabs_end_tab('mode', 'status');

######################################################################
# Link to Unbound
print &ui_tabs_start_tab('mode', 'unbound');
print $text{'pihole_unbounddesc'},"<p>\n";
my $ups = &pihole_config("dns/upstreams") || [ ];
my $want = &unbound_upstream();
my @only = grep { $_ eq $want } @$ups;
# Path of a query, with the state of each hop
print &brand_flow([
	[ 'desktop', $text{'brand_fclients'}, $text{'brand_fnet'}, 'ok' ],
	[ 'pihole', "Pi-hole", &text('brand_fport', 53),
	  &pihole_ftl_running() ? 'ok' : 'off' ],
	[ 'unbound', "Unbound",
	  $want ? "<tt>".&html_escape($want)."</tt>" : $text{'pihole_nolisten'},
	  !$upid ? 'off' : !@only ? 'off' : @$ups == 1 ? 'ok' : 'mid' ],
	[ 'globe', $text{'brand_froot'}, $text{'brand_fdnssec'},
	  $upid ? 'ok' : 'off' ],
	]);
print &ui_table_start($text{'pihole_link'}, "width=100%", 2);
print &ui_table_row($text{'pihole_upstreams'},
	join("<br>", map { "<tt>".&html_escape($_)."</tt>" } @$ups) || "-");
print &ui_table_row($text{'pihole_unboundaddr'},
	$want ? "<tt>".&html_escape($want)."</tt>" : $text{'pihole_nolisten'});
print &ui_table_row($text{'pihole_linkstate'},
	@only && @$ups == 1 ? &good($text{'pihole_linkok'}) :
	@only ? &warnc($text{'pihole_linkmixed'}) :
		&bad($text{'pihole_linknone'}));

my $rev = &pihole_config("dns/revServers") || [ ];
my @hidden = &hidden_local_zones($rev);
print &ui_table_row($text{'pihole_zones'},
	@hidden ? &bad(&text('pihole_zoneshidden', join(", ", map {
			"<tt>".&html_escape(&display_name($_))."</tt>" }
			@hidden))) :
		  &good($text{'pihole_zonesok'}));
print &ui_table_row($text{'pihole_revservers'},
	join("<br>", map { "<tt>".&html_escape($_)."</tt>" } @$rev) ||
	$text{'pihole_none'});
print &ui_table_end();

print &ui_buttons_start();
if ($want && !(@only && @$ups == 1)) {
	print &ui_buttons_row("pihole_unbound.cgi", $text{'pihole_useunbound'},
		&text('pihole_useunbounddesc', "<tt>".&html_escape($want).
					       "</tt>"),
		[ [ "do", "upstreams" ] ]);
	}
if ($want && @hidden) {
	print &ui_buttons_row("pihole_unbound.cgi", $text{'pihole_fixzones'},
		$text{'pihole_fixzonesdesc'}, [ [ "do", "zones" ] ]);
	}
print &ui_buttons_end();
print &ui_tabs_end_tab('mode', 'unbound');

######################################################################
# Allowed and denied domains
print &ui_tabs_start_tab('mode', 'domains');
print &ui_form_start("pihole_search.cgi");
print "<b>$text{'pihole_search'}</b> ",&ui_textbox("domain", undef, 40)," ",
      &ui_submit($text{'pihole_searchok'});
print &ui_form_end();

my $dl = &pihole_get("/domains") || { };
my @rows;
foreach my $d (sort { $a->{'domain'} cmp $b->{'domain'} }
		    @{$dl->{'domains'} || [ ]}) {
	push(@rows, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => join("/", $d->{'type'}, $d->{'kind'},
				  $d->{'domain'}) },
		"<tt>".&html_escape($d->{'domain'})."</tt>",
		$d->{'type'} eq 'deny' ? &bad($text{'pihole_deny'})
				       : &good($text{'pihole_allow'}),
		$text{'pihole_kind_'.$d->{'kind'}} || &html_escape($d->{'kind'}),
		$d->{'enabled'} ? $text{'yes'} : $text{'no'},
		&html_escape($d->{'comment'}),
		]);
	}
print &ui_form_columns_table("pihole_domain.cgi",
	[ [ "delete", $text{'pihole_deletesel'} ] ], 1, undef, undef,
	[ "", $text{'pihole_domain'}, $text{'pihole_dtype'},
	  $text{'pihole_dkind'}, $text{'pihole_enabled'},
	  $text{'pihole_comment'} ],
	100, \@rows, undef, 0, undef, $text{'pihole_nodomains'});

print &ui_form_start("pihole_domain.cgi", "post");
print &ui_hidden("add", 1);
print &ui_table_start($text{'pihole_adddomain'}, "width=100%", 2);
print &ui_table_row($text{'pihole_domain'},
	&ui_textarea("domain", undef, 3, 50).
	"<br><small>$text{'pihole_domaindesc'}</small>");
print &ui_table_row($text{'pihole_dtype'},
	&ui_select("list", "deny/exact",
		   [ [ "deny/exact", $text{'pihole_denyexact'} ],
		     [ "deny/regex", $text{'pihole_denyregex'} ],
		     [ "allow/exact", $text{'pihole_allowexact'} ],
		     [ "allow/regex", $text{'pihole_allowregex'} ] ]));
print &ui_table_row($text{'pihole_comment'}, &ui_textbox("comment", undef, 50));
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'pihole_addok'} ] ]);
print &ui_tabs_end_tab('mode', 'domains');

######################################################################
# Blocklists and allowlists
print &ui_tabs_start_tab('mode', 'lists');
my $ll = &pihole_get("/lists") || { };
@rows = ( );
foreach my $l (@{$ll->{'lists'} || [ ]}) {
	my $st = $l->{'status'};
	push(@rows, [
		{ 'type' => 'checkbox', 'name' => 'd',
		  'value' => $l->{'type'}."/".$l->{'address'} },
		"<tt>".&html_escape($l->{'address'})."</tt>".
		  ($l->{'comment'} ? "<br><small>".&html_escape($l->{'comment'}).
				     "</small>" : ""),
		$l->{'type'} eq 'allow' ? &good($text{'pihole_allow'})
					: $text{'pihole_block'},
		$l->{'enabled'} ? $text{'yes'} : &warnc($text{'no'}),
		int($l->{'number'}),
		&pihole_time($l->{'date_updated'}),
		$text{"pihole_lstatus".$st} || &html_escape($st),
		]);
	}
print &ui_form_columns_table("pihole_list.cgi",
	[ [ "enable", $text{'pihole_enablesel'} ],
	  [ "disable", $text{'pihole_disablesel'} ],
	  [ "delete", $text{'pihole_deletesel'} ] ], 1, undef, undef,
	[ "", $text{'pihole_laddress'}, $text{'pihole_dtype'},
	  $text{'pihole_enabled'}, $text{'pihole_lnumber'},
	  $text{'pihole_lupdated'}, $text{'pihole_lstatus'} ],
	100, \@rows, undef, 0, undef, $text{'pihole_nolists'});

print &ui_form_start("pihole_list.cgi", "post");
print &ui_hidden("add", 1);
print &ui_table_start($text{'pihole_addlist'}, "width=100%", 2);
print &ui_table_row($text{'pihole_laddress'},
	&ui_textarea("address", undef, 3, 70).
	"<br><small>$text{'pihole_laddressdesc'}</small>");
print &ui_table_row($text{'pihole_dtype'},
	&ui_radio("type", "block", [ [ "block", $text{'pihole_block'} ],
				    [ "allow", $text{'pihole_allow'} ] ]));
print &ui_table_row($text{'pihole_comment'}, &ui_textbox("comment", undef, 50));
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'pihole_addok'} ] ]);
print &ui_buttons_start();
print &ui_buttons_row("pihole_action.cgi", $text{'pihole_gravitynow'},
		      $text{'pihole_gravitydesc'}, [ [ "action", "gravity" ] ]);
print &ui_buttons_end();
print &ui_tabs_end_tab('mode', 'lists');

######################################################################
# Query log
print &ui_tabs_start_tab('mode', 'queries');
my $len = $in{'qlen'} =~ /^\d+$/ && $in{'qlen'} <= 1000 ? $in{'qlen'} :
	  $config{'pihole_queries'} || 100;
print &ui_form_start("pihole.cgi");
print &ui_hidden("mode", "queries");
print "$text{'pihole_qdomain'} ",&ui_textbox("qdomain", $in{'qdomain'}, 25),
      " $text{'pihole_qclient'} ",&ui_textbox("qclient", $in{'qclient'}, 15),
      " ",&ui_select("qstatus", $in{'qstatus'},
		     [ [ "", $text{'pihole_qall'} ],
		       [ "blocked", $text{'pihole_qblockedonly'} ],
		       [ "permitted", $text{'pihole_qpermitted'} ] ]),
      " ",&ui_select("qlen", $len, [ 50, 100, 250, 500, 1000 ]),
      " ",&ui_submit($text{'pihole_qfilter'});
print &ui_form_end();

my $qs = "/queries?length=".($in{'qstatus'} ? 1000 : $len);
$qs .= "&domain=".&urlize($in{'qdomain'}) if ($in{'qdomain'} =~ /\S/);
$qs .= "&client_ip=".&urlize($in{'qclient'}) if ($in{'qclient'} =~ /\S/);
my $ql = &pihole_get($qs) || { };
my %blocked = map { $_, 1 } ( "GRAVITY", "REGEX", "DENYLIST",
	"EXTERNAL_BLOCKED_IP", "EXTERNAL_BLOCKED_NULL", "EXTERNAL_BLOCKED_NXRA",
	"GRAVITY_CNAME", "REGEX_CNAME", "DENYLIST_CNAME", "SPECIAL_DOMAIN",
	"DBBUSY", "EXTERNAL_BLOCKED_EDE15" );
@rows = ( );
foreach my $r (@{$ql->{'queries'} || [ ]}) {
	my $isb = $blocked{$r->{'status'}};
	next if ($in{'qstatus'} eq 'blocked' && !$isb);
	next if ($in{'qstatus'} eq 'permitted' && $isb);
	last if (@rows >= $len);
	my $dom = $r->{'domain'};
	my $act = $isb ?
		&ui_link("pihole_domain.cgi?add=1&list=allow/exact&domain=".
			 &urlize($dom), $text{'pihole_qallow'}) :
		&ui_link("pihole_domain.cgi?add=1&list=deny/exact&domain=".
			 &urlize($dom), $text{'pihole_qdeny'});
	push(@rows, [
		&make_date(int($r->{'time'})),
		&html_escape($r->{'type'}),
		"<tt>".&html_escape($dom)."</tt>",
		&html_escape($r->{'client'}->{'name'} || $r->{'client'}->{'ip'}),
		&brand_badge($r->{'status'},
			$isb ? "#dd4b39" :
			$r->{'status'} =~ /CACHE/ ? "#3164b4" :
			$r->{'status'} =~ /FORWARDED/ ? "#00a65a" : "#6b7fa8"),
		&html_escape($r->{'reply'}->{'type'}).
		  ($r->{'reply'}->{'time'} > 0 ?
		   sprintf(" (%.1f ms)", $r->{'reply'}->{'time'} * 1000) : ""),
		&html_escape($r->{'upstream'} || ""),
		$act,
		]);
	}
print &ui_columns_table([ $text{'pihole_qtime'}, $text{'record_type'},
			  $text{'pihole_domain'}, $text{'pihole_qclient'},
			  $text{'pihole_qstatus'}, $text{'pihole_qreply'},
			  $text{'pihole_upstream'}, "" ],
			100, \@rows, undef, 0, undef, $text{'pihole_noqueries'});
print &ui_tabs_end_tab('mode', 'queries');

######################################################################
# Clients
print &ui_tabs_start_tab('mode', 'clients');
my $cl = &pihole_get("/clients") || { };
my $gr = &pihole_get("/groups") || { };
my %gname = map { $_->{'id'}, $_->{'name'} } @{$gr->{'groups'} || [ ]};
@rows = ( );
foreach my $c (@{$cl->{'clients'} || [ ]}) {
	push(@rows, [
		{ 'type' => 'checkbox', 'name' => 'd', 'value' => $c->{'client'} },
		"<tt>".&html_escape($c->{'client'})."</tt>",
		&html_escape($c->{'name'} || ""),
		&html_escape(join(", ", map { $gname{$_} || $_ }
					    @{$c->{'groups'} || [ ]})),
		&html_escape($c->{'comment'}),
		]);
	}
print &ui_form_columns_table("pihole_client.cgi",
	[ [ "delete", $text{'pihole_deletesel'} ] ], 1, undef, undef,
	[ "", $text{'pihole_client'}, $text{'pihole_cname'},
	  $text{'pihole_groups'}, $text{'pihole_comment'} ],
	100, \@rows, undef, 0, undef, $text{'pihole_noclients'});
print &ui_form_start("pihole_client.cgi", "post");
print &ui_hidden("add", 1);
print &ui_table_start($text{'pihole_addclient'}, "width=100%", 2);
print &ui_table_row($text{'pihole_client'},
	&ui_textbox("client", $in{'client'}, 40).
	"<br><small>$text{'pihole_clientdesc'}</small>");
print &ui_table_row($text{'pihole_groups'},
	&ui_select("groups", [ 0 ],
		   [ map { [ $_->{'id'}, &html_escape($_->{'name'}) ] }
			 @{$gr->{'groups'} || [ ]} ], 3, 1));
print &ui_table_row($text{'pihole_comment'}, &ui_textbox("comment", undef, 50));
print &ui_table_end();
print &ui_form_end([ [ undef, $text{'pihole_addok'} ] ]);
print &ui_tabs_end_tab('mode', 'clients');

######################################################################
# Network overview and DHCP leases
print &ui_tabs_start_tab('mode', 'network');
my $nd = &pihole_get("/network/devices?max_devices=500&max_addresses=10") || { };
@rows = ( );
foreach my $d (sort { $b->{'lastQuery'} <=> $a->{'lastQuery'} }
		    @{$nd->{'devices'} || [ ]}) {
	my @ips = map { &html_escape($_->{'ip'}).
			($_->{'name'} ? " (".&html_escape($_->{'name'}).")" : "")
		      } @{$d->{'ips'} || [ ]};
	push(@rows, [
		join("<br>", @ips) || "-",
		"<tt>".&html_escape($d->{'hwaddr'})."</tt>",
		&html_escape($d->{'macVendor'} || ""),
		&html_escape($d->{'interface'}),
		&pihole_time($d->{'firstSeen'}),
		&pihole_time($d->{'lastQuery'}),
		int($d->{'numQueries'}),
		$d->{'ips'} && @{$d->{'ips'}} ?
		  &ui_link("pihole_client.cgi?add=1&client=".
			   &urlize($d->{'ips'}->[0]->{'ip'}),
			   $text{'pihole_asclient'}) : "",
		]);
	}
print &ui_subheading($text{'pihole_devices'});
print &ui_columns_table([ $text{'pihole_ips'}, $text{'pihole_mac'},
			  $text{'pihole_vendor'}, $text{'pihole_iface'},
			  $text{'pihole_firstseen'}, $text{'pihole_lastquery'},
			  $text{'pihole_queries'}, "" ],
			100, \@rows, undef, 0, undef, $text{'pihole_nodevices'});

my $dhcpon = &pihole_config("dhcp/active");
print &ui_subheading($text{'pihole_leases'});
if (!$dhcpon) {
	print $text{'pihole_nodhcp'},"<p>\n";
	}
my $le = &pihole_get("/dhcp/leases") || { };
@rows = ( );
foreach my $l (@{$le->{'leases'} || [ ]}) {
	push(@rows, [
		&html_escape($l->{'ip'}),
		&html_escape($l->{'name'} eq '*' ? "" : $l->{'name'}),
		"<tt>".&html_escape($l->{'hwaddr'})."</tt>",
		$l->{'expires'} ? &pihole_time($l->{'expires'})
				: $text{'pihole_infinite'},
		]);
	}
print &ui_columns_table([ $text{'pihole_ip'}, $text{'pihole_hostname'},
			  $text{'pihole_mac'}, $text{'pihole_expires'} ],
			100, \@rows, undef, 0, undef, $text{'pihole_noleases'});
if (@rows && &can_edit('local')) {
	print &ui_link("edit_batch.cgi?source=leases",
		       $text{'pihole_importleases'}),"<p>\n";
	}
print &ui_tabs_end_tab('mode', 'network');

print &ui_tabs_end(1);
&ui_print_footer("", $text{'index_return'});
