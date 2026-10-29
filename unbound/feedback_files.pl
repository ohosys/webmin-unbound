# feedback_files.pl
# Files to attach to a Webmin feedback / bug report

do 'unbound-lib.pl';

sub feedback_files
{
return grep { -e $_ } &get_config_files();
}

1;
