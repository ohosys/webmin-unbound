#!/usr/local/bin/perl
# Delete several local-data records at once

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'drecs_err'});
&can_edit('local') || &error($text{'local_ecannot'});
my @d = split(/\0/, $in{'d'});
@d || &error($text{'drecs_enone'});

&begin_change();
# Find all records first, because deleting one shifts the line numbers (and
# so the IDs) of those after it
my @recs;
foreach my $sel (@d) {
	my ($id, $old) = split(/\t/, $sel, 2);
	my $r = &find_record_by_id($id, $old) || &error($text{'record_egone'});
	push(@recs, $r);
	}
foreach my $r (@recs) {
	&delete_directive($r->{'dir'});
	}
my $count = scalar(@recs);
&commit_change();
&live_sync_names(map { &record_live_names($_) } @recs);
&webmin_log("delete", "records", $in{'zone'}, { 'count' => $count });
&redirect($in{'orphans'} ? "edit_local.cgi?orphans=1" :
	  "edit_local.cgi?zone=".&urlize($in{'zone'}));
