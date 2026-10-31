#!/usr/bin/perl
# Checks that button labels are not shared with other texts.
# The Authentic theme picks a button's colour and icon from the text key whose
# value matches the label; a shared label makes that choice random, so for
# example the Stop button could turn green.
use strict;
use warnings;
use Cwd qw(abs_path); my $dir = abs_path($0); $dir =~ s/[^\/]+$//;
my $mod = "${dir}../unbound";

# Text keys used as button labels in the module's pages
my %buttons = map { $_, 1 } qw(index_stop index_start index_apply);
foreach my $file (glob("$mod/*.cgi $mod/*.pl")) {
	open(my $fh, "<", $file) or die "$file: $!";
	my $src = do { local $/; <$fh> };
	close($fh);
	while ($src =~ /(?:ui_submit|ui_buttons_row|ui_form_end|ui_confirmation_form)\s*\((.*?)\)\s*;/sg) {
		my $args = $1;
		$buttons{$1}++ while ($args =~ /\$text\{'([a-z0-9_]+)'\}/g);
		}
	}

my $fail = 0;
foreach my $lang (glob("$mod/lang/*")) {
	my %t;
	open(my $fh, "<", $lang) or die "$lang: $!";
	while (<$fh>) { chomp; $t{$1} = $2 if (/^([^=]+)=(.*)$/); }
	close($fh);
	foreach my $b (sort keys %buttons) {
		next if (!defined($t{$b}));
		my @same = grep { $_ ne $b && $t{$_} eq $t{$b} } sort keys %t;
		if (@same) {
			print "FAIL $lang: button $b shares its label with @same\n";
			$fail++;
			}
		}
	}
print $fail ? "$fail label test(s) failed\n"
	    : "label tests passed (".scalar(keys %buttons)." button labels)\n";
exit($fail ? 1 : 0);
