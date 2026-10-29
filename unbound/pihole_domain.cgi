#!/usr/local/bin/perl
# Add or delete allowed and denied domains in Pi-hole

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_derr'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});

my $back = $in{'return'} =~ /^(queries|domains)$/ ? $in{'return'} :
	   $ENV{'REQUEST_METHOD'} eq 'GET' ? 'queries' : 'domains';
if ($in{'add'}) {
	$in{'list'} =~ /^(allow|deny)\/(exact|regex)$/ ||
		&error($text{'pihole_elist'});
	my ($type, $kind) = ($1, $2);
	my @doms = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
			split(/\r?\n/, $in{'domain'});
	@doms || &error($text{'pihole_enodomain'});
	foreach my $d (@doms) {
		if ($kind eq 'exact') {
			&valid_domain($d) && $d !~ /\*/ ||
				&error(&text('pihole_edomain', &html_escape($d)));
			}
		else {
			eval { qr/$d/ };
			!$@ || &error(&text('pihole_eregex', &html_escape($d)));
			}
		}
	my ($d, $err) = &pihole_api("POST", "/domains/$type/$kind",
		{ 'domain' => \@doms, 'comment' => $in{'comment'},
		  'enabled' => \1 });
	&error($err) if ($err);
	&webmin_log("pihole_add", $type, join(" ", @doms));
	}
elsif ($in{'delete'}) {
	my @d = split(/\0/, $in{'d'});
	@d || &error($text{'pihole_enone'});
	foreach my $v (@d) {
		my ($type, $kind, $dom) = split(/\//, $v, 3);
		$type =~ /^(allow|deny)$/ && $kind =~ /^(exact|regex)$/ ||
			&error($text{'pihole_elist'});
		my ($r, $err) = &pihole_api("DELETE", "/domains/$type/$kind/".
					    &pihole_path_part($dom));
		&error($err) if ($err);
		}
	&webmin_log("pihole_delete", "domains", scalar(@d));
	}
&redirect("pihole.cgi?mode=$back");
