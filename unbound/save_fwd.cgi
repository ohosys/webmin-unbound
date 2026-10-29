#!/usr/local/bin/perl
# Create, update or delete a forward-zone or stub-zone

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'fwd_err'});
my $t = $in{'type'};
$t eq 'forward' || $t eq 'stub' || &error($text{'fwd_etype'});
&can_edit($t) || &error($text{'fwd_ecannot'});

&begin_change();
my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause($t."-zone", $in{'old'}) ||
		&error($text{'fwd_egone'});
	}

if ($in{'delete'}) {
	my $old = &canonical_name(&find_clause_value("name", $c));
	&delete_clause($c);
	# Don't leave behind settings that only existed for this zone
	if ($old ne '.' && !&find_zone_clause($t eq 'forward' ? "stub-zone"
							     : "forward-zone", $old)) {
		&set_domain_listed("private-domain", $old, 0);
		&set_domain_listed("domain-insecure", $old, 0);
		}
	&commit_change();
	&webmin_log("delete", $t, $in{'old'});
	&redirect("index.cgi?mode=$t");
	exit;
	}

# Validate inputs
my $name = $in{'name'};
$name =~ s/^\s+|\s+$//g;
&valid_domain($name) && $name !~ /\*/ ||
	&error(&text('fwd_ename', &html_escape($name)));
$name = &canonical_name($name);
my $clash = &find_zone_clause($t."-zone", $name);
$clash && $clash ne $c && &error($text{'fwd_eclash'});

my @addrs = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		 split(/\r?\n/, $in{'addrs'});
foreach my $a (@addrs) {
	&valid_server_addr($a) ||
		&error(&text('fwd_eaddr', &html_escape($a)));
	}
my @hosts = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		 split(/\r?\n/, $in{'hosts'});
foreach my $h (@hosts) {
	my ($hn) = split(/[@#]/, $h);
	&valid_domain($hn) && $h =~ /^[A-Za-z0-9\.\-_]+(@\d+)?(#[A-Za-z0-9\.\-_]+)?$/ ||
		&error(&text('fwd_ehost', &html_escape($h)));
	}
@addrs || @hosts || &error($text{'fwd_enone'});
foreach my $f ('prime', 'first', 'tls', 'nocache') {
	$in{$f} eq '' || $in{$f} eq 'yes' || $in{$f} eq 'no' ||
		&error($text{'fwd_eyesno'});
	}

# Build the directive list
my @dirs = ( [ "name", &quote_value($name, 1) ] );
push(@dirs, map { [ $t."-addr", $_ ] } @addrs);
push(@dirs, map { [ $t."-host", &quote_value($_) ] } @hosts);
push(@dirs, [ "stub-prime", $in{'prime'} ]) if ($t eq 'stub');
push(@dirs, [ $t."-first", $in{'first'} ]);
push(@dirs, [ $t."-tls-upstream", $in{'tls'} ]);
push(@dirs, [ $t."-no-cache", $in{'nocache'} ]);

if ($in{'new'}) {
	&create_clause($t."-zone", [ grep { $_->[1] ne '' } @dirs ]);
	}
else {
	# Update in place, one directive name at a time
	my %byname;
	foreach my $d (@dirs) {
		push(@{$byname{$d->[0]}}, $d->[1]) if ($d->[1] ne '');
		$byname{$d->[0]} ||= [ ];
		}
	foreach my $n (sort keys %byname) {
		&save_directives([ $c ], $n, $byname{$n}, $c);
		}
	}

# Private addresses and DNSSEC for internal zones
if ($name ne '.' && defined($in{'privdom'})) {
	if (!$in{'new'}) {
		my $old = &canonical_name($in{'old'});
		if ($old ne $name) {
			&set_domain_listed("private-domain", $old, 0);
			&set_domain_listed("domain-insecure", $old, 0);
			}
		}
	&set_domain_listed("private-domain", $name, $in{'privdom'});
	&set_domain_listed("domain-insecure", $name, $in{'insecure'});
	}

&commit_change();
&webmin_log($in{'new'} ? "create" : "modify", $t, $name);
&redirect("index.cgi?mode=$t");
