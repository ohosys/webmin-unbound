#!/usr/local/bin/perl
# Find which Pi-hole lists and domain rules match a domain

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_serr'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});
my $dom = $in{'domain'};
$dom =~ s/^\s+|\s+$//g;
&valid_domain($dom) || &error(&text('pihole_edomain', &html_escape($dom)));

my $r = &pihole_get("/search/".&pihole_path_part($dom)."?partial=false&N=50");
$r || &error($pihole_last_error);
my $s = $r->{'search'} || { };

&ui_print_header(undef, $text{'pihole_searchtitle'}, "");
print &text('pihole_searchfor', "<tt>".&html_escape($dom)."</tt>"),"<p>\n";
my @rows;
foreach my $d (@{$s->{'domains'} || [ ]}) {
	push(@rows, [ $text{'pihole_rule'},
		      "<tt>".&html_escape($d->{'domain'})."</tt>",
		      $d->{'type'} eq 'deny' ? $text{'pihole_deny'}
					     : $text{'pihole_allow'},
		      $d->{'enabled'} ? $text{'yes'} : $text{'no'} ]);
	}
foreach my $g (@{$s->{'gravity'} || [ ]}) {
	push(@rows, [ $text{'pihole_listmatch'},
		      "<tt>".&html_escape($g->{'address'})."</tt>",
		      $g->{'type'} eq 'allow' ? $text{'pihole_allow'}
					      : $text{'pihole_block'},
		      $g->{'enabled'} ? $text{'yes'} : $text{'no'} ]);
	}
print &ui_columns_table([ $text{'pihole_matchtype'}, $text{'pihole_matchwhat'},
			  $text{'pihole_dtype'}, $text{'pihole_enabled'} ],
			100, \@rows, undef, 0, undef,
			$text{'pihole_nomatch'});
if (&valid_domain($dom) && $dom !~ /\*/) {
	print &ui_form_start("pihole_domain.cgi", "post");
	print &ui_hidden("return", "domains");
	print &pihole_quick_button("allow", $dom)," ",
	      &pihole_quick_button("deny", $dom);
	print &ui_form_end();
	print "<p>\n";
	}
&ui_print_footer("pihole.cgi?mode=domains", $text{'pihole_return'});
