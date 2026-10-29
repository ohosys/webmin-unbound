#!/usr/local/bin/perl
# Create, update or delete a client view, and the access-control-view lines
# that send clients to it

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'view_err'});
&can_edit('views') || &error($text{'view_ecannot'});

&begin_change();
my $c;
my $oldname;
if (!$in{'new'}) {
	$c = &find_zone_clause("view", $in{'old'}) || &error($text{'view_egone'});
	$oldname = &find_clause_value("name", $c);
	}

# Other access-control-view lines (for other views) are kept as they are
my @otheracv = map { $_->{'value'} }
	grep { my @w = split(/\s+/, join(" ", @{$_->{'values'}}));
	       !defined($oldname) || $w[1] ne $oldname }
	     &find_server("access-control-view");

if ($in{'delete'}) {
	&delete_clause($c);
	&save_server("access-control-view", \@otheracv);
	&commit_change();
	&webmin_log("delete", "view", $oldname);
	&redirect("index.cgi?mode=views");
	exit;
	}

# Validate inputs
my $name = $in{'name'};
$name =~ /^[A-Za-z0-9_\-\.]+$/ || &error($text{'view_ename'});
my $clash = &find_zone_clause("view", $name);
$clash && $clash ne $c && &error($text{'view_eclash'});

my @clients = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		   split(/\r?\n/, $in{'clients'});
foreach my $n (@clients) {
	&valid_netblock($n) || &error(&text('access_enet', &html_escape($n)));
	}
my @zones;
foreach my $l (split(/\r?\n/, $in{'zones'})) {
	$l =~ s/^\s+|\s+$//g;
	next if ($l eq '');
	my ($zn, $zt) = &split_values($l);
	&valid_domain($zn) || &error(&text('local_ename', &html_escape($zn)));
	&indexof($zt, @local_zone_types) >= 0 ||
		&error(&text('view_ezonetype', &html_escape($l)));
	push(@zones, &quote_value(&canonical_name($zn), 1)." ".$zt);
	}
my @data;
foreach my $l (split(/\r?\n/, $in{'data'})) {
	$l =~ s/^\s+|\s+$//g;
	next if ($l eq '');
	my $rr = &parse_rr($l);
	&valid_domain($rr->{'name'}) && $rr->{'type'} =~ /^[A-Z0-9]+$/ &&
	    $rr->{'data'} =~ /\S/ ||
		&error(&text('view_edata', &html_escape($l)));
	$l =~ /'/ && &error($text{'record_equote'});
	push(@data, $l =~ /"/ ? "'$l'" : "\"$l\"");
	}
foreach my $f ('first') {
	$in{$f} eq '' || $in{$f} eq 'yes' || $in{$f} eq 'no' ||
		&error($text{'fwd_eyesno'});
	}

my @dirs = ( [ "name", &quote_value($name, 1) ],
	     [ "view-first", $in{'first'} ] );
push(@dirs, map { [ "local-zone", $_ ] } @zones);
push(@dirs, map { [ "local-data", $_ ] } @data);
if ($in{'new'}) {
	&create_clause("view", [ grep { $_->[1] ne '' } @dirs ]);
	}
else {
	my %byname = ( "name" => [ ], "view-first" => [ ], "local-zone" => [ ],
		       "local-data" => [ ] );
	foreach my $d (@dirs) {
		push(@{$byname{$d->[0]}}, $d->[1]) if ($d->[1] ne '');
		}
	foreach my $n (sort keys %byname) {
		&save_directives([ $c ], $n, $byname{$n}, $c);
		}
	}
&save_server("access-control-view",
	     [ @otheracv, map { $_." ".$name } @clients ]);

&commit_change();
&webmin_log($in{'new'} ? "create" : "modify", "view", $name);
&redirect("index.cgi?mode=views");
