#!/usr/local/bin/perl
# Show server status, statistics and cache tools (via unbound-control)

require './unbound-lib.pl';
&can_edit('control') || &error($text{'control_ecannot'});
&ui_print_header(undef, $text{'control_title'}, "");

if (!&is_unbound_running()) {
	print "<b>",$text{'control_edown'},"</b><p>\n";
	&ui_print_footer("", $text{'index_return'});
	exit;
	}
if (!&control_available()) {
	print "<b>",$text{'control_eavail'},"</b><p>\n";
	print &text('control_eavail2', "edit_opts.cgi?page=rc"),"<p>\n";
	&ui_print_footer("", $text{'index_return'});
	exit;
	}

# Status
my ($ok, $out) = &control_command("status");
print &ui_table_start($text{'control_status'}, "width=100%", 2);
foreach my $l (split(/\r?\n/, $out)) {
	next if ($l !~ /^([^:]+):\s*(.*)$/);
	print &ui_table_row(&html_escape($1), &html_escape($2));
	}
print &ui_table_end();

# Key statistics
my ($sok, $sout) = &control_command("stats_noreset");
if ($sok) {
	my %st;
	foreach my $l (split(/\r?\n/, $sout)) {
		$st{$1} = $2 if ($l =~ /^(\S+)=(\S+)$/);
		}
	my $q = $st{'total.num.queries'} || 0;
	my $hits = $st{'total.num.cachehits'} || 0;
	print &ui_table_start($text{'control_stats'}, "width=100%", 4);
	print &ui_table_row($text{'stat_queries'}, $q);
	print &ui_table_row($text{'stat_hits'},
		$hits.($q ? sprintf(" (%.1f%%)", 100*$hits/$q) : ""));
	print &ui_table_row($text{'stat_miss'},
		$st{'total.num.cachemiss'} || 0);
	print &ui_table_row($text{'stat_prefetch'},
		$st{'total.num.prefetch'} || 0);
	print &ui_table_row($text{'stat_expired'},
		$st{'total.num.expired'} || 0);
	print &ui_table_row($text{'stat_rectime'},
		$st{'total.recursion.time.avg'} ne '' ?
		  sprintf("%.3f s", $st{'total.recursion.time.avg'}) : "-");
	print &ui_table_row($text{'stat_memrrset'},
		&nice_size($st{'mem.cache.rrset'} || 0));
	print &ui_table_row($text{'stat_memmsg'},
		&nice_size($st{'mem.cache.message'} || 0));
	print &ui_table_row($text{'stat_uptime'},
		$st{'time.up'} ne '' ? int($st{'time.up'})." s" : "-");
	print &ui_table_end();
	}

# Cache and lookup tools
print &ui_form_start("control_run.cgi", "post");
print &ui_table_start($text{'control_tools'}, "width=100%", 2);
print &ui_table_row($text{'control_name'},
	&ui_textbox("name", undef, 40));
print &ui_table_row($text{'control_qtype'},
	&ui_select("qtype", "A", [ "A", "AAAA", "MX", "TXT", "NS", "CNAME",
				  "PTR", "SRV", "SOA", "CAA" ]));
print &ui_table_end();
print &ui_form_end([
	[ "flush", $text{'control_flush'} ],
	[ "flush_zone", $text{'control_flushzone'} ],
	[ "lookup", $text{'control_lookup'} ],
	&has_command("dig") ? ( [ "dig", $text{'control_dig'} ] ) : ( ),
	]);

# Global actions
print &ui_buttons_start();
foreach my $a ("flush_bogus", "flush_negative", "flush_infra",
	       "list_local_zones", "list_local_data", "list_forwards",
	       "list_stubs", "list_auth_zones", "dump_requestlist") {
	print &ui_buttons_row("control_run.cgi", $text{'control_'.$a},
			      $text{'control_'.$a.'desc'},
			      &ui_hidden("action", $a));
	}
print &ui_buttons_end();

&ui_print_footer("", $text{'index_return'});
