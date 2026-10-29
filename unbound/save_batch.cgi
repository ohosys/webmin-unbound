#!/usr/local/bin/perl
# Import many local records at once, or preview what would be imported

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'batch_err'});
&can_edit('local') || &error($text{'local_ecannot'});

my $zone = &find_local_zone($in{'zone'}) || &error($text{'local_egone'});
my $zname = &canonical_name($zone->{'name'});
my $ttl = "";
if (!$in{'ttl_def'}) {
	$in{'ttl'} =~ /^\d+$/ || &error($text{'record_ettl'});
	$ttl = $in{'ttl'};
	}

# Turn the chosen source into a list of records to add
my @add;	# [ name, type, data, ptr-ip-or-undef, source-line ]
my @bad;	# [ line, reason ]
if ($in{'source'} eq 'text' && $in{'format'} eq 'rr') {
	foreach my $l (split(/\r?\n/, $in{'text'})) {
		$l =~ s/^\s+|\s+$//g;
		next if ($l eq '' || $l =~ /^[;#]/);
		if ($l =~ /'/) {
			push(@bad, [ $l, $text{'record_equote'} ]);
			next;
			}
		my $rr = &parse_rr($l);
		if (&indexof($rr->{'type'}, @record_types) < 0) {
			push(@bad, [ $l, $text{'record_etype'} ]);
			next;
			}
		if (!&valid_domain($rr->{'name'}) && $rr->{'name'} ne '@') {
			push(@bad, [ $l, &text('record_ename',
					       &html_escape($rr->{'name'})) ]);
			next;
			}
		if ($rr->{'type'} eq 'A' && !&check_ipaddress($rr->{'data'}) ||
		    $rr->{'type'} eq 'AAAA' && !&valid_ip6($rr->{'data'}) ||
		    $rr->{'data'} !~ /\S/) {
			push(@bad, [ $l, $text{'batch_edata'} ]);
			next;
			}
		push(@add, [ &full_record_name($rr->{'name'}, $zname),
			     $rr->{'type'}, $rr->{'data'}, undef, $l,
			     $rr->{'ttl'} ]);
		}
	}
else {
	my @lines;
	if ($in{'source'} eq 'text') {
		@lines = &parse_hosts_lines($in{'text'});
		# Report lines that are not comments but don't start with an IP
		foreach my $l (split(/\r?\n/, $in{'text'})) {
			my $c = $l;
			$c =~ s/#.*$//;
			$c =~ s/^\s+|\s+$//g;
			next if ($c eq '');
			my @w = split(/\s+/, $c);
			if (!&valid_ip($w[0]) || @w < 2) {
				push(@bad, [ $l, $text{'batch_ehostline'} ]);
				}
			}
		}
	elsif ($in{'source'} eq 'hosts') {
		@lines = &parse_hosts_lines(&read_file_contents("/etc/hosts"));
		}
	elsif ($in{'source'} eq 'leases') {
		@lines = map { [ $_->[0], $_->[1] ] } &list_dhcp_leases();
		}
	else {
		&error($text{'batch_esource'});
		}
	foreach my $h (@lines) {
		my ($ip, @names) = @$h;
		# Skip loopback and similar entries from /etc/hosts
		next if ($ip =~ /^(127\.|::1$|ff0|fe00)/i);
		# Lease and hosts files are not checked when read, so check here
		if (!&valid_ip($ip)) {
			push(@bad, [ join(" ", @$h), $text{'record_eip'} ]);
			next;
			}
		my $first = 1;
		foreach my $n (@names) {
			if (!&valid_domain($n) || $n =~ /\*/) {
				push(@bad, [ join(" ", @$h),
					     &text('record_ename',
						   &html_escape($n)) ]);
				next;
				}
			# Short names are put in the selected zone
			my $full = $n =~ /\./ && $n !~ /\.$/ ? lc($n)."."
							      : &full_record_name($n, $zname);
			push(@add, [ $full, &check_ipaddress($ip) ? "A" : "AAAA",
				     $ip, $first && $in{'ptr'} ? $ip : undef,
				     join(" ", @$h) ]);
			$first = 0;
			}
		}
	}
@add || @bad || &error($text{'batch_enone'});

# Work out what happens to each record
my @existing = &list_local_records();
my @plan;	# [ action, &add ]
my %seen;
foreach my $a (@add) {
	my $key = $a->[0]."/".$a->[1]."/".lc($a->[2]);
	if ($seen{$key}++) {
		push(@plan, [ 'dup', $a ]);
		next;
		}
	my @same = grep { $_->{'type'} eq $a->[1] &&
			  &canonical_name($_->{'name'}) eq $a->[0] } @existing;
	if (@same && $in{'dup'} ne 'replace') {
		push(@plan, [ 'skip', $a ]);
		}
	elsif (@same) {
		push(@plan, [ 'replace', $a, \@same ]);
		}
	else {
		push(@plan, [ 'add', $a ]);
		}
	}

if (!$in{'preview'}) {
	# Make the changes, in one checked step
	&begin_change();
	# First remove every record being replaced, in one pass over the
	# current config (deleting shifts line numbers, so IDs can't be reused)
	my %replace = map { $_->[1]->[0]."/".$_->[1]->[1] => 1 }
			  grep { $_->[0] eq 'replace' } @plan;
	foreach my $r (&list_local_records()) {
		next if ($r->{'type'} eq 'REVPTR');
		if ($replace{&canonical_name($r->{'name'})."/".$r->{'type'}}) {
			&delete_directive($r->{'dir'});
			}
		}
	my @existing = &list_local_records();
	my (@data, @ptrs, @live);
	foreach my $p (@plan) {
		next if ($p->[0] ne 'add' && $p->[0] ne 'replace');
		my $a = $p->[1];
		push(@data, &local_data_value($a->[0],
				$a->[5] ne '' ? $a->[5] : $ttl,
				$a->[1], $a->[2]));
		push(@live, $a->[0]);
		if ($a->[3]) {
			my $had = grep { $_->{'type'} eq 'REVPTR' &&
					 $_->{'ip'} eq $a->[3] } @existing;
			if (!$had) {
				push(@ptrs, &local_data_ptr_value($a->[3],
							$a->[0], $ttl));
				push(@live, &reverse_name($a->[3]));
				}
			}
		}
	if (@data) {
		&save_directives([ &find_clauses("server") ], "local-data",
			[ ( map { $_->{'value'} } &find_server("local-data") ),
			  @data ], &get_default_server());
		}
	if (@ptrs) {
		&save_directives([ &find_clauses("server") ], "local-data-ptr",
			[ ( map { $_->{'value'} }
				&find_server("local-data-ptr") ), @ptrs ],
			&get_default_server());
		}
	&commit_change();
	&live_sync_names(@live);
	&webmin_log("import", "records", $zname,
		    { 'count' => scalar(@data), 'source' => $in{'source'} });
	}

# Show the result or preview
&ui_print_header(&html_escape(&display_name($zname)),
		 $in{'preview'} ? $text{'batch_ptitle'} : $text{'batch_rtitle'},
		 "");
my %count;
$count{$_->[0]}++ foreach (@plan);
print &text($in{'preview'} ? 'batch_psummary' : 'batch_rsummary',
	    $count{'add'} || 0, $count{'replace'} || 0,
	    ($count{'skip'} || 0) + ($count{'dup'} || 0), scalar(@bad)),"<p>\n";
my @rows;
foreach my $p (@plan) {
	my $a = $p->[1];
	push(@rows, [ $text{'batch_a'.$p->[0]},
		      &html_escape($a->[0]), $a->[1], &html_escape($a->[2]),
		      $a->[3] ? $text{'yes'} : "" ]);
	}
foreach my $b (@bad) {
	push(@rows, [ "<b>".$text{'batch_abad'}."</b>",
		      &html_escape($b->[0]), "", $b->[1], "" ]);
	}
print &ui_columns_table([ $text{'batch_action'}, $text{'record_name'},
			  $text{'record_type'}, $text{'record_value'},
			  $text{'batch_ptrcol'} ], 100, \@rows);

if ($in{'preview'}) {
	# Same form again, ready to import
	print &ui_form_start("save_batch.cgi", "post");
	foreach my $k ("zone", "source", "format", "text", "ptr", "dup",
		       "ttl", "ttl_def") {
		print &ui_hidden($k, $in{$k});
		}
	print &ui_form_end([ [ "import", $text{'batch_import'} ] ]);
	}
&ui_print_footer("edit_local.cgi?zone=".&urlize($zname), $text{'local_return'},
		 "index.cgi?mode=local", $text{'index_return'});
