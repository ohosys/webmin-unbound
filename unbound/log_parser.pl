# log_parser.pl
# Functions for parsing this module's logs

do 'unbound-lib.pl';

# parse_webmin_log(user, script, action, type, object, &params)
# Converts logged information from this module into human-readable text
sub parse_webmin_log
{
my ($user, $script, $action, $type, $object, $p) = @_;
my $o = "<tt>".&html_escape($object)."</tt>";
if ($type eq 'record') {
	return &text("log_${action}_record",
		     "<tt>".&html_escape($p->{'name'})."</tt>",
		     &html_escape($p->{'type'}), $o);
	}
elsif ($type eq 'records' && $action eq 'import') {
	return &text('log_import_records', $p->{'count'}, $o);
	}
elsif ($type eq 'records') {
	return &text('log_delete_records', $p->{'count'}, $o);
	}
elsif ($action eq 'include') {
	return &text('log_include', "<tt>".&html_escape($object)."</tt>");
	}
elsif ($action eq 'opts') {
	return &text('log_opts', $text{$type.'_title'} || &html_escape($type));
	}
elsif ($action eq 'control') {
	return &text('log_control', "<tt>".&html_escape($type)."</tt>",
		     $object ne '' ? $o : "");
	}
elsif ($action =~ /^pihole_(delete|enablelist|disablelist)$/) {
	return &text("log_$action", &html_escape($object),
		     &html_escape($type));
	}
elsif ($action eq 'manual') {
	return &text('log_manual', $o);
	}
elsif ($text{"log_${action}_${type}"}) {
	return &text("log_${action}_${type}", $o);
	}
elsif ($text{"log_${action}"}) {
	return $text{"log_${action}"};
	}
return undef;
}

1;
