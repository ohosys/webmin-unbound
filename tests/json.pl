#!/usr/bin/perl
# Checks the built-in JSON codec of pihole-lib.pl against JSON::PP
use strict;
use warnings;
use JSON::PP;
our (%config, %text);
sub has_command { 0 }
sub read_file_contents { "" }
sub convert_to_json { die "must not be called\n" }
sub convert_from_json { die "must not be called\n" }
use Cwd qw(abs_path); my $dir = abs_path($0); $dir =~ s/[^\/]+$//;
do "${dir}../unbound/pihole-lib.pl" or die $@ || $!;
no warnings "once"; $main::pihole_json_mod = 0;
my $fail = 0;
my $pp = JSON::PP->new->utf8->canonical;
my @samples = (
  '{"blocking":"enabled","timer":null,"took":0.000123}',
  '{"queries":[{"id":1,"domain":"café.example","status":"GRAVITY","reply":{"type":"IP","time":1.5e-3}}],"cursor":-1}',
  '{"a":[true,false,null,"x\"y\\\\z\n\t",[],{}],"e":"😀 emoji","n":-12,"f":3.25E+2}',
  "{\"utf8raw\":\"citt\xc3\xa0 \xe2\x82\xac\"}",
  '[]', '[1,2,3]', ' { "sp" : [ 1 , "2" ] } ',
);
foreach my $j (@samples) {
	my $mine = eval { &main::pihole_from_json($j) };
	if ($@) { print "FAIL decode $j: $@"; $fail++; next; }
	my $ref = $pp->decode($j);
	my $a = $pp->encode(JSON::PP->new->decode(JSON::PP->new->encode($mine) =~ s/^/ /r)) ;
	# Normalise booleans for comparison
	my $norm = sub { my $x = JSON::PP->new->canonical->allow_nonref->encode($_[0]);
			 $x =~ s/\btrue\b/1/g; $x =~ s/\bfalse\b/0/g; $x };
	if ($norm->($mine) ne $norm->($ref)) {
		print "FAIL decode $j\n  mine ", $norm->($mine), "\n  ref  ", $norm->($ref), "\n"; $fail++;
		}
	else { print "ok decode ", substr($j,0,40), "\n"; }
}
# Encoding: our output must decode (by JSON::PP, latin1 bytes as Webmin does) to the same data
my $num = 5; my $str = "007"; my $mixed = 3; my $x = "$mixed";
my @data = (
  { domain => "ads.example", comment => "a \"b\" \\ c\n", enabled => \1, groups => [0, 2], type => "deny" },
  { blocking => \0, timer => 300 },
  { s => $str, n => $num, m => $mixed, u => "\x{20ac}\x{1F600}" },
  [ undef, \1, "" ],
);
foreach my $d (@data) {
	my $mine = &main::pihole_to_json($d);
	my $back = JSON::PP->new->latin1->decode($mine);
	my $ref = JSON::PP->new->latin1->canonical->encode($d);
	if ($mine ne $ref) { print "FAIL encode\n  mine $mine\n  ref  $ref\n"; $fail++; }
	else { print "ok encode $mine\n"; }
}
print $fail ? "$fail FAILED\n" : "all JSON tests passed\n";
exit($fail ? 1 : 0);
