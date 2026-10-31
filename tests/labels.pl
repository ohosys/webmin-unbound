#!/usr/bin/perl
# Checks that the labels of the main buttons are not shared with other texts.
# The Authentic theme picks a button's colour and icon from the text key whose
# value matches the label; a shared label makes that choice random, so for
# example the Stop button could turn green.
use strict;
use warnings;
use Cwd qw(abs_path); my $dir = abs_path($0); $dir =~ s/[^\/]+$//;
my @buttons = qw(index_stop index_start index_apply);
my $fail = 0;
foreach my $lang (glob("${dir}../unbound/lang/*")) {
	my %t;
	open(my $fh, "<", $lang) or die "$lang: $!";
	while (<$fh>) { chomp; $t{$1} = $2 if (/^([^=]+)=(.*)$/); }
	close($fh);
	foreach my $b (@buttons) {
		next if (!defined($t{$b}));
		my @same = grep { $_ ne $b && $t{$_} eq $t{$b} } sort keys %t;
		if (@same) {
			print "FAIL $lang: $b shares its label with @same\n";
			$fail++;
			}
		}
	}
print $fail ? "$fail label test(s) failed\n" : "label tests passed\n";
exit($fail ? 1 : 0);
