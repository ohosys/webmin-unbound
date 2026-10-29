#!/usr/local/bin/perl
# Check the configuration with unbound-checkconf, and show diagnostics for
# common problems: port 53 conflicts, the system resolver, DNSSEC and
# remote control

require './unbound-lib.pl';
&can_edit('apply') || &error($text{'check_ecannot'});
&ui_print_header(undef, $text{'check_title'}, "");

# Config syntax
print &ui_subheading($text{'check_syntax'});
if (!&has_command($config{'unbound_checkconf'})) {
	print &text('check_ecmd', "<tt>".&html_escape(
		$config{'unbound_checkconf'})."</tt>"),"<p>\n";
	}
else {
	my @errs = &check_config();
	if (@errs) {
		print "<b>",$text{'check_errs'},"</b><p>\n";
		print "<pre>",&html_escape(join("\n", @errs)),"</pre>\n";
		}
	else {
		print "<b>",$text{'check_ok'},"</b><p>\n";
		}
	print $text{'check_files'},"<ul>\n";
	foreach my $f (&get_config_files()) {
		print "<li><tt>",&html_escape($f),"</tt>",
		      (-e $f ? "" : " ".$text{'check_missing'}),"</li>\n";
		}
	print "</ul>\n";
	}

# Diagnostics table
print &ui_subheading($text{'diag_title'});
print &ui_columns_start([ $text{'diag_check'}, $text{'diag_result'},
			  $text{'diag_advice'} ]);
my $ok = "<font color=green>$text{'diag_ok'}</font>";
my $warn = "<font color=orange><b>$text{'diag_warn'}</b></font>";
my $bad = "<font color=red><b>$text{'diag_bad'}</b></font>";

# Who listens on the DNS port?
my $port = &find_server_value("port") || 53;
my @l = &port_listeners($port);
my @others = grep { $_->[2] ne 'unbound' && $_->[2] ne '?' } @l;
my $running = &is_unbound_running();
if (!&has_command("ss")) {
	print &ui_columns_row([ &text('diag_port', $port), "-",
				$text{'diag_noss'} ]);
	}
elsif (@others) {
	print &ui_columns_row([ &text('diag_port', $port), $bad,
		&text('diag_portother', join(", ", &unique(map {
			"<tt>".&html_escape($_->[2])."</tt> (".
			&html_escape($_->[1]).")" } @others))) ]);
	}
elsif ($running && !@l) {
	print &ui_columns_row([ &text('diag_port', $port), $warn,
				$text{'diag_portnone'} ]);
	}
else {
	print &ui_columns_row([ &text('diag_port', $port), $ok,
		join(", ", &unique(map { &html_escape($_->[0]." ".$_->[1]) } @l)) ||
		$text{'diag_notrunning'} ]);
	}

# System resolver
my %res = &get_resolver_status();
my $nslist = join(", ", map { "<tt>".&html_escape($_)."</tt>" }
			    @{$res{'nameservers'}}) || "-";
my $fw = &dns_forwarder();
if ($fw && $port != 53) {
	# Something like Pi-hole answers on port 53 and uses Unbound, so the
	# system should point at that rather than at Unbound
	print &ui_columns_row([ $text{'diag_resolver'},
		$res{'uses_local'} ? $ok : "-",
		&text($res{'uses_local'} ? 'diag_resfwd' : 'diag_resfwdother',
		      $nslist, $fw->{'name'}) ]);
	}
elsif ($port != 53) {
	print &ui_columns_row([ $text{'diag_resolver'}, "-",
				&text('diag_resport', $nslist, $port) ]);
	}
elsif ($res{'uses_local'}) {
	print &ui_columns_row([ $text{'diag_resolver'}, $ok,
				&text('diag_resok', $nslist) ]);
	}
elsif ($res{'resolved'}) {
	print &ui_columns_row([ $text{'diag_resolver'}, $warn,
				&text('diag_resresolved', $nslist) ]);
	}
else {
	print &ui_columns_row([ $text{'diag_resolver'}, $warn,
		&text('diag_resother', $nslist).
		(&foreign_available("net") ?
			"<br>".&ui_link("resolver.cgi", $text{'diag_resfix'})
			: "") ]);
	}

# DNSSEC trust anchor
my $anchor = &find_server_value("auto-trust-anchor-file") ||
	     &find_server_value("trust-anchor-file");
if (!$anchor) {
	print &ui_columns_row([ $text{'diag_dnssec'}, $warn,
				$text{'diag_noanchor'} ]);
	}
elsif (!-r $anchor) {
	print &ui_columns_row([ $text{'diag_dnssec'}, $bad,
		&text('diag_anchormissing', "<tt>".&html_escape($anchor).
					    "</tt>") ]);
	}
else {
	print &ui_columns_row([ $text{'diag_dnssec'}, $ok,
		&text('diag_anchorok', "<tt>".&html_escape($anchor)."</tt>") ]);
	}

# Remote control
if (!$running) {
	print &ui_columns_row([ $text{'diag_control'}, "-",
				$text{'diag_notrunning'} ]);
	}
elsif (&control_available()) {
	print &ui_columns_row([ $text{'diag_control'}, $ok,
				$text{'diag_controlok'} ]);
	}
else {
	print &ui_columns_row([ $text{'diag_control'}, $warn,
		&text('control_eavail2', "edit_opts.cgi?page=rc") ]);
	}

# DNS forwarder like Pi-hole that uses Unbound
if ($fw) {
	my @probs = &forwarder_problems();
	my $ups = join(", ", map { "<tt>".&html_escape($_)."</tt>" }
				 @{$fw->{'upstreams'}}) || "-";
	if (@probs) {
		print &ui_columns_row([ $fw->{'name'}, $bad,
					join("<br>\n", @probs) ]);
		}
	elsif (!@{$fw->{'to_unbound'}}) {
		print &ui_columns_row([ $fw->{'name'}, $warn,
			&text('diag_fwdnone', $fw->{'name'}, $ups) ]);
		}
	elsif (@{$fw->{'upstreams'}} > @{$fw->{'to_unbound'}}) {
		print &ui_columns_row([ $fw->{'name'}, $warn,
			&text('diag_fwdmixed', $fw->{'name'}, $ups) ]);
		}
	else {
		print &ui_columns_row([ $fw->{'name'}, $ok,
			&text('diag_fwdok', $fw->{'name'}, $ups).
			($config{'forwarder_flush'} ? " ".$text{'diag_fwdflush'}
						    : "") ]);
		}
	}

# Forwarding everything to servers from unbound-resolvconf.service,
# which the Pi-hole guide says to turn off
foreach my $c (&list_zone_clauses("forward-zone")) {
	next if (&canonical_name($c->{'name'}) ne '.');
	my $file = $c->{'clause'}->{'file'};
	next if ($file !~ /resolvconf_resolvers\.conf$/);
	print &ui_columns_row([ $text{'diag_recursion'}, $warn,
		&text('diag_resolvconf', &html_escape($file)) ]);
	}

# Internal zones whose private answers get removed
if (&find_server("private-address")) {
	my @pz = &private_zone_problems();
	if (@pz) {
		print &ui_columns_row([ $text{'diag_privzone'}, $bad,
			&text('diag_privzonebad', join(", ", map {
				"<tt>".&html_escape(&display_name($_))."</tt>"
				} @pz)) ]);
		}
	elsif (grep { &canonical_name($_->{'name'}) ne '.' }
		    (&list_zone_clauses("forward-zone"),
		     &list_zone_clauses("stub-zone"))) {
		print &ui_columns_row([ $text{'diag_privzone'}, $ok,
					$text{'diag_privzoneok'} ]);
		}
	}

# AppArmor on Debian and Ubuntu only lets Unbound write some places
if (-r "/etc/apparmor.d/usr.sbin.unbound") {
	my @ap = &apparmor_problems();
	if (@ap) {
		print &ui_columns_row([ $text{'diag_apparmor'}, $warn,
			join("<br>\n", map {
				&text('diag_apparmorbad',
				      $_->[1] eq 'log' ? $text{'diag_apparmorlog'}
					: &text('diag_apparmorzone', "<tt>".
					  &html_escape(&display_name($_->[2])).
					  "</tt>"),
				      &html_escape($_->[0])) } @ap) ]);
		}
	else {
		print &ui_columns_row([ $text{'diag_apparmor'}, $ok,
					$text{'diag_apparmorok'} ]);
		}
	}

# SELinux on RHEL-family systems only lets Unbound bind some ports
if (&selinux_mode() && -r "/etc/pihole/pihole.toml") {
	# Pi-hole does not support SELinux, so with Pi-hole it must be turned off
	print &ui_columns_row([ $text{'diag_selinux'}, $warn,
				$text{'diag_selinuxpihole'} ]);
	}
elsif (&selinux_mode()) {
	# Unbound on its own : only the port matters
	my @sp = &selinux_port_problems();
	if (@sp && !defined($sp[0])) {
		print &ui_columns_row([ $text{'diag_selinux'}, $warn,
					$text{'diag_selinuxnosemanage'} ]);
		}
	elsif (@sp) {
		print &ui_columns_row([ $text{'diag_selinux'}, $warn,
			join("<br>\n", map {
				&text('diag_selinuxbad', uc($_->[0]), $_->[1],
				      "<tt>".&html_escape($_->[2])."</tt>",
				      "<tt>".&html_escape(
					&selinux_fix_command($_))."</tt>") }
			     @sp) ]);
		}
	else {
		print &ui_columns_row([ $text{'diag_selinux'}, $ok,
					$text{'diag_selinuxok'} ]);
		}
	}

# Config files in Unbound's directories that nothing includes
my @unread = &unread_config_files();
if (@unread) {
	my %dirs = map { (my $d = $_) =~ s/\/[^\/]+$//; $d, 1 } @unread;
	print &ui_columns_row([ $text{'diag_unread'}, $warn,
		&text('diag_unreadbad', join(", ", map {
			"<tt>".&html_escape($_)."</tt>" } @unread),
		      "<tt>".&html_escape(&get_config_file())."</tt>").
		(&can_edit('manual') ? "<br>".join(" ", map {
			&ui_link("fix_include.cgi?dir=".&urlize($_),
				 &text('diag_unreadfix', &html_escape($_))) }
			sort keys %dirs) : "") ]);
	}

# Perl JSON module, used by the Pi-hole pages. Optional : the module has its
# own reader, but the standard one is faster
if (-r "/etc/pihole/pihole.toml") {
	require './pihole-lib.pl';
	if (&pihole_json_module()) {
		print &ui_columns_row([ $text{'diag_json'}, $ok,
					$text{'diag_jsonok'} ]);
		}
	else {
		my $inst = &foreign_available("cpan") ?
			" ".&ui_link("../cpan/download.cgi?source=3&cpan=JSON::PP".
				     "&mode=2&return=/$module_name/check.cgi".
				     "&returndesc=".&urlize($text{'check_title'}),
				     $text{'diag_jsoninst'}) : "";
		print &ui_columns_row([ $text{'diag_json'}, $ok,
					$text{'diag_jsonown'}.$inst ]);
		}
	}

# Socket buffers larger than the kernel allows, like so-rcvbuf: 1m in the
# Pi-hole guide
my @bufbad;
my $anybuf;
foreach my $b ([ "so-rcvbuf", "net.core.rmem_max" ],
	       [ "so-sndbuf", "net.core.wmem_max" ]) {
	my $want = &parse_size(&find_server_value($b->[0]));
	next if (!$want);
	$anybuf++;
	(my $proc = "/proc/sys/".$b->[1]) =~ s/\./\//g;
	my $max = &read_file_contents($proc);
	$max =~ s/\s+//g;
	next if ($max !~ /^\d+$/ || $max >= $want);
	push(@bufbad, &text('diag_rmembad', $b->[0], $want, $b->[1], $max));
	}
if (@bufbad) {
	print &ui_columns_row([ $text{'diag_rmem'}, $warn,
				join("<br>\n", @bufbad) ]);
	}
elsif ($anybuf) {
	print &ui_columns_row([ $text{'diag_rmem'}, $ok, $text{'diag_rmemok'} ]);
	}

# Access control
my @acl = &find_server("access-control");
my $ifaces = join(" ", map { $_->{'values'}->[0] } &find_server("interface"));
if (!@acl && $ifaces =~ /0\.0\.0\.0|::0|::(\s|$)/) {
	print &ui_columns_row([ $text{'access_title'}, $warn,
				$text{'diag_noacl'} ]);
	}
else {
	print &ui_columns_row([ $text{'access_title'}, $ok,
		&text('diag_acl', scalar(@acl)) ]);
	}
print &ui_columns_end();

&ui_print_footer("", $text{'index_return'});
