# cgi_args.pl
# Default arguments for pages, so that Webmin's search can link to them

do 'unbound-lib.pl';

sub cgi_args
{
my ($cgi) = @_;
if ($cgi eq 'edit_opts.cgi') {
	return 'page=net';
	}
elsif ($cgi eq 'edit_local.cgi') {
	my ($z) = &list_local_zones();
	return $z ? 'zone='.&urlize(&canonical_name($z->{'name'})) : 'new=1';
	}
elsif ($cgi eq 'edit_fwd.cgi') {
	my ($z) = &list_zone_clauses("forward-zone");
	return $z ? 'type=forward&name='.&urlize($z->{'name'})
		  : 'type=forward&new=1';
	}
elsif ($cgi eq 'edit_auth.cgi' || $cgi eq 'edit_rpz.cgi') {
	my $t = $cgi eq 'edit_rpz.cgi' ? 'rpz' : 'auth-zone';
	my ($z) = &list_zone_clauses($t);
	return $z ? 'name='.&urlize($z->{'name'}) : 'new=1';
	}
elsif ($cgi eq 'edit_view.cgi') {
	my ($v) = &list_views();
	return $v ? 'name='.&urlize($v->{'name'}) : 'new=1';
	}
elsif ($cgi eq 'edit_record.cgi' || $cgi =~ /^save_|^delete_|_run\.cgi$/) {
	return 'none';
	}
return '';
}

1;
