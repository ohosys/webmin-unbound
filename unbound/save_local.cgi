#!/usr/local/bin/perl
# Create, update or delete a local zone

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'local_err'});
&can_edit('local') || &error($text{'local_ecannot'});

my $type = $in{'type'};
if (!$in{'delete'}) {
	&indexof($type, @local_zone_types) >= 0 ||
		&error($text{'local_etype'});
	}

&begin_change();
my ($zone, $name, @revlive);
if ($in{'new'}) {
	$name = $in{'name'};
	$name =~ s/^\s+|\s+$//g;
	&valid_domain($name) && $name !~ /\*/ ||
		&error(&text('local_ename', &html_escape($name)));
	$name = &canonical_name($name);
	&find_local_zone($name) && &error($text{'local_eclash'});
	&save_directives([ &find_clauses("server") ], "local-zone",
		[ ( map { $_->{'value'} } &find_server("local-zone") ),
		  &quote_value($name, 1)." ".$type ],
		&get_default_server());
	}
else {
	$zone = &find_local_zone($in{'old'}) || &error($text{'local_egone'});
	$name = &canonical_name($zone->{'name'});
	if ($in{'delete'}) {
		# Remove the zone and the records in it
		my @recs = &records_for_zone($name);
		push(@revlive, map { &record_live_names($_) }
				   grep { $_->{'type'} eq 'REVPTR' } @recs);
		foreach my $r (sort { $b->{'dir'}->{'line'} <=>
				      $a->{'dir'}->{'line'} } @recs) {
			&delete_directive($r->{'dir'});
			}
		&delete_directive($zone->{'dir'});
		}
	else {
		&update_directive($zone->{'dir'},
				  &quote_value($zone->{'name'}, 1)." ".$type);
		}
	}
&commit_change();
if ($in{'new'}) {
	&live_zone("add", $name, $type);
	}
elsif ($in{'delete'}) {
	&live_zone("remove", $name);
	&live_sync_names(@revlive);
	}
elsif ($type ne $zone->{'type'}) {
	# Changing the type drops the zone's data, so put it back
	&live_zone("remove", $name);
	&live_zone("add", $name, $type);
	&live_sync_names(map { &record_live_names($_) }
			     &records_for_zone($name));
	}
&webmin_log($in{'new'} ? "create" : $in{'delete'} ? "delete" : "modify",
	    "local", $name);
&redirect($in{'delete'} ? "index.cgi?mode=local"
			: "edit_local.cgi?zone=".&urlize($name));
