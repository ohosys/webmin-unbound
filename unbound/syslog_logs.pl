# syslog_logs.pl
# Tells the System Logs and Log File viewer modules about Unbound's log file

do 'unbound-lib.pl';

# syslog_getlogs()
# Returns the log file set in unbound.conf, if any
sub syslog_getlogs
{
my $file = &find_server_value("logfile");
return ( ) if (!$file || $file !~ /^\//);
return ( { 'file' => $file,
	   'active' => &find_server_value("use-syslog") ne "yes",
	   'desc' => $text{'syslog_desc'} } );
}

1;
