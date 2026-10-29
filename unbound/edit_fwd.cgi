#!/usr/local/bin/perl
# Show a forward-zone or stub-zone

require './unbound-lib.pl';
&ReadParse();
my $t = $in{'type'};
$t eq 'forward' || $t eq 'stub' || &error($text{'fwd_etype'});
&can_edit($t) || &error($text{'fwd_ecannot'});

my $c;
if (!$in{'new'}) {
	$c = &find_zone_clause($t."-zone", $in{'name'}) ||
		&error($text{'fwd_egone'});
	}
&ui_print_header($c ? &html_escape(&display_name(&canonical_name(
				&find_clause_value("name", $c)))) : undef,
		 $text{$t.'_'.($c ? 'edit' : 'create')}, "");

print $text{$t.'_desc'},"<p>\n";
print &ui_form_start("save_fwd.cgi", "post");
print &ui_hidden("type", $t);
print &ui_hidden("new", $in{'new'});
print &ui_hidden("old", $in{'name'});
print &ui_table_start($text{$t.'_header'}, "width=100%", 2);

my $empty = { 'members' => [ ] };
$c ||= $empty;
print &ui_table_row($text{'fwd_name'},
	&ui_textbox("name", $c eq $empty ? "" :
			    &find_clause_value("name", $c), 40).
	"<br><small>".$text{'fwd_namedesc'}."</small>");
print &ui_table_row($text{'fwd_addrs'},
	&ui_textarea("addrs", join("\n", &find_clause_values($t."-addr", $c)),
		     4, 40)."<br><small>".$text{'fwd_addrsdesc'}."</small>");
print &ui_table_row($text{'fwd_hosts'},
	&ui_textarea("hosts", join("\n", &find_clause_values($t."-host", $c)),
		     3, 40)."<br><small>".$text{'fwd_hostsdesc'}."</small>");
if ($t eq 'stub') {
	print &ui_table_row($text{'fwd_prime'},
		&yesno_input("prime", &find_clause_value("stub-prime", $c)));
	}
print &ui_table_row($text{'fwd_first'},
	&yesno_input("first", &find_clause_value($t."-first", $c)));
print &ui_table_row($text{'fwd_tls'},
	&yesno_input("tls", &find_clause_value($t."-tls-upstream", $c)));
print &ui_table_row($text{'fwd_nocache'},
	&yesno_input("nocache", &find_clause_value($t."-no-cache", $c)));
# Internal zones: keep private addresses in answers and skip DNSSEC
my $zn = $c eq $empty ? undef : &find_clause_value("name", $c);
if (!defined($zn) || &canonical_name($zn) ne '.') {
	my ($pd, $di);
	if (defined($zn)) {
		$pd = &domain_listed("private-domain", $zn);
		$di = &domain_listed("domain-insecure", $zn);
		}
	else {
		# Defaults for a new zone: on, as it's usually a local server
		$pd = $di = 1;
		}
	print &ui_table_row($text{'fwd_privdom'},
		&ui_yesno_radio("privdom", $pd ? 1 : 0).
		"<br><small>".$text{'fwd_privdomdesc'}."</small>");
	print &ui_table_row($text{'fwd_insecure'},
		&ui_yesno_radio("insecure", $di ? 1 : 0).
		"<br><small>".$text{'fwd_insecuredesc'}."</small>");
	}
if ($c ne $empty) {
	print &ui_table_row($text{'local_file'},
		"<tt>".&html_escape($c->{'file'})."</tt>");
	}

print &ui_table_end();
print &ui_form_end($in{'new'} ? [ [ "create", $text{'create'} ] ]
			      : [ [ "save", $text{'save'} ],
				  [ "delete", $text{'delete'} ] ]);

&ui_print_footer("index.cgi?mode=$t", $text{'index_return'});
