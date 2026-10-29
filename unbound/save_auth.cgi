#!/usr/local/bin/perl
# Create, update or delete an auth-zone

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'auth_err'});
&can_edit('auth') || &error($text{'auth_ecannot'});

&begin_change();
my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause("auth-zone", $in{'old'}) ||
		&error($text{'auth_egone'});
	}

if ($in{'delete'}) {
	&delete_clause($c);
	&commit_change();
	&webmin_log("delete", "auth", $in{'old'});
	&redirect("index.cgi?mode=auth");
	exit;
	}

# Validate inputs
my $name = $in{'name'};
$name =~ s/^\s+|\s+$//g;
&valid_domain($name) && $name !~ /\*/ ||
	&error(&text('fwd_ename', &html_escape($name)));
$name = &canonical_name($name);
my $clash = &find_zone_clause("auth-zone", $name);
$clash && $clash ne $c && &error($text{'fwd_eclash'});

my @prims = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		 split(/\r?\n/, $in{'primaries'});
foreach my $p (@prims) {
	&valid_server_addr($p) ||
		&error(&text('fwd_eaddr', &html_escape($p)));
	}
my @urls = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		split(/\r?\n/, $in{'urls'});
foreach my $u (@urls) {
	$u =~ /^https?:\/\/[^\s"'#]+$/ ||
		&error(&text('auth_eurl', &html_escape($u)));
	}
my @notify = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
		  split(/\r?\n/, $in{'notify'});
foreach my $n (@notify) {
	&valid_netblock($n) || &error(&text('auth_enotify', &html_escape($n)));
	}
my $zf = "";
if (!$in{'zonefile_def'}) {
	$zf = $in{'zonefile'};
	$zf =~ /^[^\s"'#]+$/ || &error($text{'auth_ezonefile'});
	}
@prims || @urls || $zf ne '' || &error($text{'auth_enone'});
foreach my $f ('downstream', 'upstream', 'fallback') {
	$in{$f} eq '' || $in{$f} eq 'yes' || $in{$f} eq 'no' ||
		&error($text{'fwd_eyesno'});
	}

# Newer Unbound versions call it primary:, older ones master:
my $pname = $c && &find_dirs("master", [ $c ]) ? "master" :
	    &version_atleast("1.19.0") ? "primary" : "master";
my @dirs = ( [ "name", &quote_value($name, 1) ] );
push(@dirs, map { [ $pname, $_ ] } @prims);
push(@dirs, map { [ "url", &quote_value($_, 1) ] } @urls);
push(@dirs, map { [ "allow-notify", $_ ] } @notify);
push(@dirs, [ "zonefile", $zf eq '' ? '' : &quote_value($zf, 1) ]);
push(@dirs, [ "for-downstream", $in{'downstream'} ]);
push(@dirs, [ "for-upstream", $in{'upstream'} ]);
push(@dirs, [ "fallback-enabled", $in{'fallback'} ]);

if ($in{'new'}) {
	&create_clause("auth-zone", [ grep { $_->[1] ne '' } @dirs ]);
	}
else {
	my %byname;
	foreach my $d (@dirs) {
		push(@{$byname{$d->[0]}}, $d->[1]) if ($d->[1] ne '');
		$byname{$d->[0]} ||= [ ];
		}
	# Clear the other spelling of primary / master
	$byname{$pname eq 'master' ? 'primary' : 'master'} = [ ];
	foreach my $n (sort keys %byname) {
		&save_directives([ $c ], $n, $byname{$n}, $c);
		}
	}

&commit_change();
&webmin_log($in{'new'} ? "create" : "modify", "auth", $name);
&redirect("index.cgi?mode=auth");
