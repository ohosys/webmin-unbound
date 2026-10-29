#!/usr/local/bin/perl
# Run one unbound-control command and show its output

require './unbound-lib.pl';
&ReadParse();
&error_setup($text{'control_err'});
&can_edit('control') || &error($text{'control_ecannot'});

# Work out which action was requested
my @named = ( "flush", "flush_zone", "lookup", "dig" );
my @global = ( "flush_bogus", "flush_negative", "flush_infra",
	       "list_local_zones", "list_local_data", "list_forwards",
	       "list_stubs", "list_auth_zones", "dump_requestlist" );
my ($action) = grep { $in{$_} } @named;
$action ||= $in{'action'};
&indexof($action, @named, @global) >= 0 || &error($text{'control_eaction'});

my @args;
if (&indexof($action, @named) >= 0) {
	my $name = $in{'name'};
	$name =~ s/^\s+|\s+$//g;
	&valid_domain($name) && $name !~ /\*/ ||
		&error(&text('control_ename', &html_escape($name)));
	@args = ( $name );
	}
@args = ( "all" ) if ($action eq 'flush_infra');

my ($ok, $out);
if ($action eq 'dig') {
	# Send a real query to the local server
	my $qtype = $in{'qtype'};
	$qtype =~ /^[A-Z]{1,10}$/ || &error($text{'control_eqtype'});
	my $port = &find_server_value("port") || 53;
	$out = &backquote_command("dig \@127.0.0.1 -p ".quotemeta($port).
				  " ".quotemeta($args[0])." ".
				  quotemeta($qtype)." 2>&1 </dev/null");
	$ok = !$?;
	}
else {
	($ok, $out) = &control_command($action, @args);
	}

&ui_print_header(undef, $text{'control_title'}, "");
print &text('control_ran', "<tt>".&html_escape(join(" ", $action, @args)).
			   "</tt>"),"<p>\n";
print $ok ? "" : "<b>".$text{'control_failed'}."</b><p>\n";
print "<pre>",&html_escape($out || $text{'control_noout'}),"</pre>\n";
if ($ok && $action =~ /^flush/ && &flush_forwarder()) {
	# Pi-hole would otherwise keep serving its own cached copies
	print &text('control_fwdflushed', &dns_forwarder()->{'name'}),"<p>\n";
	}
&webmin_log("control", $action, $args[0]) if ($action =~ /^flush/);
&ui_print_footer("control.cgi", $text{'control_return'});
