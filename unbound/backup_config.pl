# backup_config.pl

do 'unbound-lib.pl';

# backup_config_files()
# Returns the config files and auth-zone files to back up
sub backup_config_files
{
my @rv = grep { -e $_ } &get_config_files();
foreach my $c (&find_clauses("auth-zone")) {
	my $zf = &find_clause_value("zonefile", $c);
	push(@rv, $zf) if ($zf && $zf =~ /^\// && -e $zf);
	}
return &unique(@rv);
}

# pre_backup(&files)
sub pre_backup
{
return undef;
}

# post_backup(&files)
sub post_backup
{
return undef;
}

# pre_restore(&files)
sub pre_restore
{
return undef;
}

# post_restore(&files)
# Apply the restored config, if the server is running
sub post_restore
{
&clear_config_cache();
return &is_unbound_running() ? &apply_configuration() : undef;
}

1;
