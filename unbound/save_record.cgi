#!/usr/local/bin/perl
# Create, update or delete one local-data record

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'record_err'});
&can_edit('local') || &error($text{'local_ecannot'});

my $zname = $in{'zone'} ne '' ? &canonical_name($in{'zone'}) : '.';
my $type = uc($in{'type'});
my $return = $in{'zone'} eq '' ? "edit_local.cgi?orphans=1"
			       : "edit_local.cgi?zone=".&urlize($zname);

&begin_change();
my $old;
if (!$in{'new'}) {
	$old = &find_record_by_id($in{'id'}, $in{'old'}) ||
		&error($text{'record_egone'});
	$type = $old->{'type'};
	}
else {
	&indexof($type, @record_types) >= 0 || &error($text{'record_etype'});
	}

my @live = $old ? &record_live_names($old) : ( );
if ($in{'delete'}) {
	&delete_directive($old->{'dir'});
	&commit_change();
	&live_sync_names(@live);
	&webmin_log("delete", "record", $zname,
		    { 'name' => $old->{'name'}, 'type' => $type });
	&redirect($return);
	exit;
	}

# TTL
my $ttl = "";
if (!$in{'ttl_def'}) {
	$in{'ttl'} =~ /^\d+$/ || &error($text{'record_ettl'});
	$ttl = $in{'ttl'};
	}

my ($name, $newval);
if ($type eq 'REVPTR') {
	&valid_ip($in{'ip'}) || &error($text{'record_eip'});
	&valid_domain($in{'name'}) && $in{'name'} ne '.' ||
		&error($text{'record_ehost'});
	$name = &canonical_name($in{'name'});
	$newval = &local_data_ptr_value($in{'ip'}, $name, $ttl);
	push(@live, &reverse_name($in{'ip'}));
	&save_or_add("local-data-ptr", $old, $newval);
	}
else {
	my $short = $in{'name'};
	$short =~ s/^\s+|\s+$//g;
	$short eq '' || $short eq '@' || &valid_domain($short) ||
		&error(&text('record_ename', &html_escape($short)));
	$name = &full_record_name($short, $zname);
	my $data;
	my $v = $in{'value'};
	$v =~ s/^\s+|\s+$//g if ($type ne 'TXT');
	if ($type eq 'A') {
		&check_ipaddress($v) || &error($text{'record_ea'});
		$data = $v;
		}
	elsif ($type eq 'AAAA') {
		&valid_ip6($v) || &error($text{'record_eaaaa'});
		$data = $v;
		}
	elsif ($type eq 'CNAME' || $type eq 'NS' || $type eq 'PTR') {
		&valid_domain($v) && $v ne '.' ||
			&error($text{'record_etarget'});
		$data = &full_record_name($v, $zname);
		}
	elsif ($type eq 'MX') {
		$in{'pref'} =~ /^\d+$/ && $in{'pref'} < 65536 ||
			&error($text{'record_epref'});
		&valid_domain($v) || &error($text{'record_etarget'});
		$data = $in{'pref'}." ".&full_record_name($v, $zname);
		}
	elsif ($type eq 'SRV') {
		foreach my $f ('prio', 'weight', 'port') {
			$in{$f} =~ /^\d+$/ && $in{$f} < 65536 ||
				&error($text{'record_e'.$f});
			}
		&valid_domain($v) || &error($text{'record_etarget'});
		$data = join(" ", $in{'prio'}, $in{'weight'}, $in{'port'},
				  &full_record_name($v, $zname));
		}
	elsif ($type eq 'TXT') {
		$v =~ s/\r?\n/ /g;
		$v =~ /\S/ || &error($text{'record_etxt'});
		$v =~ /'/ && &error($text{'record_equote'});
		$data = &txt_strings($v);
		}
	elsif ($type eq 'CAA') {
		$in{'flags'} =~ /^\d+$/ && $in{'flags'} < 256 ||
			&error($text{'record_eflags'});
		$in{'tag'} =~ /^(issue|issuewild|iodef)$/ ||
			&error($text{'record_etag'});
		$v =~ /'/ && &error($text{'record_equote'});
		$data = $in{'flags'}." ".$in{'tag'}." ".&txt_strings($v);
		}
	if ($type eq 'CNAME') {
		# A CNAME can't share its name with other records
		foreach my $r (&list_local_records()) {
			next if ($old && $r->{'dir'} eq $old->{'dir'});
			next if ($r->{'type'} eq 'REVPTR');
			if (&canonical_name($r->{'name'}) eq $name) {
				&error($text{'record_ecname'});
				}
			}
		}
	$newval = &local_data_value($name, $ttl, $type, $data);
	push(@live, $name);
	&save_or_add("local-data", $old, $newval);

	# Also add a reverse record, if requested
	if ($in{'new'} && $in{'rev'} && ($type eq 'A' || $type eq 'AAAA')) {
		&save_or_add("local-data-ptr", undef,
			     &local_data_ptr_value($v, $name, $ttl));
		push(@live, &reverse_name($v));
		}
	}

&commit_change();
&live_sync_names(@live);
&webmin_log($in{'new'} ? "create" : "modify", "record", $zname,
	    { 'name' => $name, 'type' => $type });
&redirect($return);

# save_or_add(directive, &old-record, value)
sub save_or_add
{
my ($dname, $old, $value) = @_;
if ($old) {
	&update_directive($old->{'dir'}, $value);
	}
else {
	my @vals = map { $_->{'value'} } &find_server($dname);
	&save_directives([ &find_clauses("server") ], $dname,
			 [ @vals, $value ], &get_default_server());
	}
}
