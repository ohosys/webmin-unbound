#!/usr/local/bin/perl
# Delete several local, forward, stub or auth zones at once

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'dzones_err'});
my $t = $in{'type'};
&indexof($t, "local", "forward", "stub", "auth", "rpz", "views") >= 0 ||
	&error($text{'fwd_etype'});
&can_edit($t) || &error($text{'fwd_ecannot'});
my @d = split(/\0/, $in{'d'});
@d || &error($text{'dzones_enone'});

&begin_change();
my @revlive;
foreach my $name (@d) {
	if ($t eq 'local') {
		my $z = &find_local_zone($name) || next;
		my @recs = &records_for_zone($name);
		push(@revlive, map { &record_live_names($_) }
				   grep { $_->{'type'} eq 'REVPTR' } @recs);
		foreach my $r (@recs) {
			&delete_directive($r->{'dir'});
			}
		&delete_directive($z->{'dir'});
		}
	else {
		my $ctype = $t eq 'rpz' ? 'rpz' : $t eq 'views' ? 'view'
							     : $t."-zone";
		my $c = &find_zone_clause($ctype, $name) || next;
		&delete_clause($c);
		if ($t eq 'views') {
			# Also stop sending clients to the deleted view
			&save_server("access-control-view",
				[ map { $_->{'value'} }
				  grep { (split(/\s+/, join(" ",
					@{$_->{'values'}})))[1] ne $name }
				  &find_server("access-control-view") ]);
			}
		}
	}
&commit_change();
&restart_needed(1) if ($t eq 'rpz');
if ($t eq 'local') {
	foreach my $name (@d) {
		&live_zone("remove", $name);
		}
	&live_sync_names(@revlive);
	}
&webmin_log("delete", $t."s", scalar(@d), { 'names' => join(" ", @d) });
&redirect("index.cgi?mode=$t");
