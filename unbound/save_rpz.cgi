#!/usr/local/bin/perl
# Create, update or delete an RPZ blocklist

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'rpz_err'});
&can_edit('rpz') || &error($text{'rpz_ecannot'});

&begin_change();
my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause("rpz", $in{'old'}) || &error($text{'rpz_egone'});
	}

if ($in{'delete'}) {
	&delete_clause($c);
	&commit_change();
	&restart_needed(1);
	&webmin_log("delete", "rpz", $in{'old'});
	&redirect("index.cgi?mode=rpz");
	exit;
	}

# Validate inputs
my $name = $in{'name'};
$name =~ s/^\s+|\s+$//g;
&valid_domain($name) && $name ne '.' && $name !~ /\*/ ||
	&error(&text('fwd_ename', &html_escape($name)));
$name = &canonical_name($name);
my $clash = &find_zone_clause("rpz", $name);
$clash && $clash ne $c && &error($text{'fwd_eclash'});

my @urls = grep { /\S/ } map { s/^\s+|\s+$//g; $_ } split(/\r?\n/, $in{'urls'});
foreach my $u (@urls) {
	$u =~ /^https?:\/\/[^\s"'#]+$/ ||
		&error(&text('auth_eurl', &html_escape($u)));
	}
my @prims = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		 split(/\r?\n/, $in{'primaries'});
foreach my $p (@prims) {
	&valid_server_addr($p) || &error(&text('fwd_eaddr', &html_escape($p)));
	}
my $zf = "";
if (!$in{'zonefile_def'}) {
	$zf = $in{'zonefile'};
	$zf =~ /^\/[^\s"'#]+$/ || &error($text{'auth_ezonefile'});
	}
@urls || @prims || $zf ne '' || &error($text{'auth_enone'});
@urls && $zf eq '' && &error($text{'rpz_eurlfile'});
my $act = $in{'action'};
$act eq '' || &indexof($act, "nxdomain", "nodata", "passthru", "drop",
		       "disabled", "cname") >= 0 || &error($text{'rpz_eaction'});
my $cname = "";
if (!$in{'cname_def'}) {
	&valid_domain($in{'cname'}) || &error($text{'rpz_ecname'});
	$cname = $in{'cname'};
	}
$act eq 'cname' && $cname eq '' && &error($text{'rpz_ecname'});
my $logname = "";
if (!$in{'logname_def'}) {
	$in{'logname'} =~ /^[A-Za-z0-9_\-\.]+$/ || &error($text{'rpz_elogname'});
	$logname = $in{'logname'};
	}
foreach my $f ('log', 'ra') {
	$in{$f} eq '' || $in{$f} eq 'yes' || $in{$f} eq 'no' ||
		&error($text{'fwd_eyesno'});
	}

my $pname = $c && &find_dirs("master", [ $c ]) ? "master" : "primary";
my @dirs = ( [ "name", &quote_value($name, 1) ] );
push(@dirs, map { [ "url", &quote_value($_, 1) ] } @urls);
push(@dirs, map { [ $pname, $_ ] } @prims);
push(@dirs, [ "zonefile", $zf eq '' ? '' : &quote_value($zf, 1) ]);
push(@dirs, [ "rpz-action-override", $act ]);
push(@dirs, [ "rpz-cname-override", $cname eq '' ? '' : &quote_value($cname, 1) ]);
push(@dirs, [ "rpz-log", $in{'log'} ]);
push(@dirs, [ "rpz-log-name", $logname eq '' ? '' : &quote_value($logname, 1) ]);
push(@dirs, [ "rpz-signal-nxdomain-ra", $in{'ra'} ]);

# RPZ only works if the respip module is loaded
&ensure_respip();

if ($in{'new'}) {
	&create_clause("rpz", [ grep { $_->[1] ne '' } @dirs ]);
	}
else {
	my %byname;
	foreach my $d (@dirs) {
		push(@{$byname{$d->[0]}}, $d->[1]) if ($d->[1] ne '');
		$byname{$d->[0]} ||= [ ];
		}
	$byname{$pname eq 'master' ? 'primary' : 'master'} = [ ];
	foreach my $n (sort keys %byname) {
		&save_directives([ $c ], $n, $byname{$n}, $c);
		}
	}

&commit_change();
&restart_needed(1);
&webmin_log($in{'new'} ? "create" : "modify", "rpz", $name);
&redirect("index.cgi?mode=rpz");
