# acl_security.pl
# Per-user permissions for the Unbound module

do 'unbound-lib.pl';

our @acl_features = ( "local", "forward", "stub", "auth", "rpz", "views",
		      "opts", "acl",
		      "control", "apply", "manual", "pihole" );

# acl_security_form(&options)
# Output HTML for editing security options for this module
sub acl_security_form
{
my ($o) = @_;
foreach my $f (@acl_features) {
	print &ui_table_row($text{'acl_'.$f},
		&ui_yesno_radio($f, $o->{$f} ? 1 : 0));
	}
}

# acl_security_save(&options)
# Parse the form for security options for this module
sub acl_security_save
{
my ($o) = @_;
foreach my $f (@acl_features) {
	$o->{$f} = $in{$f} ? 1 : 0;
	}
}

1;
