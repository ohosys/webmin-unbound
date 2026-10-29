#!/usr/local/bin/perl
# Save a page of global options

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'opts_err'});
&can_edit('opts') || &error($text{'opts_ecannot'});
my %pages = &option_pages();
my $page = $pages{$in{'page'}} || &error($text{'opts_epage'});
my ($cname, @opts) = @$page;

# Validate everything first, so nothing is written on an error
my @changes;
my $i = 0;
foreach my $o (@opts) {
	my ($name, $type, $extra) = @$o;
	my $label = $text{'opt_'.$name} || $name;
	my @vals;
	if ($type eq 'yesno') {
		my $v = $in{"o_$i"};
		$v eq '' || $v eq 'yes' || $v eq 'no' ||
			&error(&text('opts_einvalid', $label));
		@vals = ( $v ) if ($v ne '');
		}
	elsif ($type eq 'select') {
		my $v = $in{"o_$i"};
		$v eq '' || &indexof($v, @$extra) >= 0 ||
			&error(&text('opts_einvalid', $label));
		@vals = ( $v ) if ($v ne '');
		}
	elsif ($type eq 'multi') {
		foreach my $v (split(/\r?\n/, $in{"o_$i"})) {
			$v =~ s/^\s+|\s+$//g;
			next if ($v eq '');
			&check_option_value($label, $extra, $v);
			push(@vals, &quote_value($v));
			}
		}
	elsif (!$in{"o_${i}_def"}) {
		my $v = $in{"o_$i"};
		$v =~ s/^\s+|\s+$//g;
		&check_option_value($label, $type, $v);
		@vals = ( &quote_value($v) );
		}
	push(@changes, [ $name, \@vals ]);
	$i++;
	}

&begin_change();
my @clauses = &find_clauses($cname);
my $newclause;
if ($cname eq 'server') {
	$newclause = &get_default_server();
	}
elsif (@clauses) {
	$newclause = $clauses[0];
	}
elsif (grep { @{$_->[1]} } @changes) {
	$newclause = &create_clause($cname, [ ]);
	@clauses = ( $newclause );
	}
foreach my $c (@changes) {
	next if (!$newclause && !@{$c->[1]});
	&save_directives(\@clauses, $c->[0], $c->[1], $newclause);
	}
&commit_change();
&webmin_log("opts", $in{'page'});
&redirect("");

# check_option_value(label, type, value)
sub check_option_value
{
my ($label, $type, $v) = @_;
my $ok;
if ($type eq 'int') {
	$ok = $v =~ /^\d+$/;
	}
elsif ($type eq 'port') {
	$ok = $v =~ /^\d+$/ && $v > 0 && $v < 65536;
	}
elsif ($type eq 'size') {
	$ok = $v =~ /^\d+[kKmMgG]?$/;
	}
elsif ($type eq 'interface') {
	$ok = &valid_interface($v);
	}
elsif ($type eq 'ip') {
	$ok = &valid_ip($v);
	}
elsif ($type eq 'netblock') {
	$ok = &valid_netblock($v);
	}
elsif ($type eq 'domain') {
	$ok = &valid_domain($v);
	}
elsif ($type eq 'file' || $type eq 'path') {
	$ok = $v =~ /^[^\s"'#]+$/;
	}
else {
	$ok = $v ne '' && $v !~ /["#]/;
	}
$ok || &error(&text('opts_evalue', &html_escape($label),
		    &html_escape($v)));
}
