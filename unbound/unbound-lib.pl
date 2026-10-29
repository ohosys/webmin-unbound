# unbound-lib.pl
# Functions for reading and updating the Unbound DNS server configuration.
#
# The config is parsed into a list of clauses (server:, forward-zone:, ...),
# each holding its directives. Every directive remembers the file and line it
# came from, so changes are made in place and the rest of the file (comments,
# ordering, includes) is left alone.

BEGIN { push(@INC, ".."); };
use WebminCore;
&init_config();
our %access = &get_module_acl();

our @known_clauses = ( "server", "remote-control", "stub-zone", "forward-zone",
		       "auth-zone", "view", "python", "dynlib", "rpz",
		       "cachedb", "dnscrypt", "dnstap", "ipset" );

our @local_zone_types = ( "static", "transparent", "typetransparent",
			  "redirect", "refuse", "deny", "inform",
			  "inform_deny", "inform_redirect",
			  "always_transparent", "block_a", "always_refuse",
			  "always_nxdomain", "always_null", "always_nodata",
			  "noview", "nodefault" );

our @access_actions = ( "allow", "allow_setrd", "allow_snoop", "allow_cookie",
			"deny", "refuse", "deny_non_local",
			"refuse_non_local" );

our @record_types = ( "A", "AAAA", "CNAME", "MX", "TXT", "PTR", "SRV", "NS",
		      "CAA" );

our ($config_loaded, @config_cache, @config_files, @config_includes);
our (%change_backup, %change_created, $change_active);
our ($dns_forwarder_cache);

######################################################################
# Parsing
######################################################################

# get_config_file()
# Returns the path to the main unbound.conf
sub get_config_file
{
return $config{'unbound_conf'};
}

# get_config()
# Returns an array ref of clause objects, parsed from all config files
sub get_config
{
if (!$config_loaded) {
	@config_cache = ( );
	@config_files = ( );
	@config_includes = ( );
	&read_config_file(&get_config_file(), \@config_cache, undef, 0);
	$config_loaded = 1;
	}
return \@config_cache;
}

# clear_config_cache()
# Forget the parsed config, so that it is re-read on the next call
sub clear_config_cache
{
$config_loaded = 0;
@config_cache = ( );
@config_files = ( );
$dns_forwarder_cache = undef;
}

# get_config_files()
# Returns the list of all files that make up the config, main file first
sub get_config_files
{
&get_config();
return @config_files;
}

# read_config_file(file, &clauses, [&current-clause], depth)
# Parses one file, appending clauses to the list. Returns the clause that is
# still open at the end of the file, because a plain include: can continue a
# clause that was started in the including file.
sub read_config_file
{
my ($file, $rv, $clause, $depth) = @_;
return $clause if ($depth > 20);
return $clause if (&indexof($file, @config_files) >= 0);
push(@config_files, $file);
return $clause if (!-r $file);
my $lref = &read_file_lines($file, 1);
my $dir = $file;
$dir =~ s/\/[^\/]+$//;
for(my $lnum=0; $lnum<@$lref; $lnum++) {
	my ($code, $comment) = &split_comment($lref->[$lnum]);
	next if ($code !~ /^(\s*)([A-Za-z0-9\-]+):\s*(.*?)\s*$/);
	my ($space, $name, $rest) = ($1, lc($2), $3);
	if (&indexof($name, @known_clauses) >= 0 &&
	    ($rest eq '' || $rest =~ /^[A-Za-z0-9\-]+:/)) {
		# Start of a new clause
		$clause = { 'type' => 'clause',
			    'name' => $name,
			    'file' => $file,
			    'line' => $lnum,
			    'eline' => $lnum,
			    'members' => [ ] };
		push(@$rv, $clause);
		if ($rest =~ /^([A-Za-z0-9\-]+):\s*(.*)$/) {
			# Directive on the same line as the clause header,
			# like "server: verbosity: 1"
			my ($dname, $dvalue) = (lc($1), $2);
			my ($prefix) = $code =~ /^(\s*[A-Za-z0-9\-]+:\s*)/;
			push(@{$clause->{'members'}},
			     &make_dir_object($dname, $dvalue, $file, $lnum,
					      $space, $comment, $clause,
					      $prefix));
			}
		}
	elsif ($name eq 'include' || $name eq 'include-toplevel') {
		my ($glob) = &split_values($rest);
		next if (!$glob);
		$glob = $dir."/".$glob if ($glob !~ /^\//);
		push(@config_includes, $glob);
		$clause = undef if ($name eq 'include-toplevel');
		foreach my $f (sort { $a cmp $b } glob($glob)) {
			$clause = &read_config_file($f, $rv, $clause,
						    $depth+1);
			}
		$clause = undef if ($name eq 'include-toplevel');
		}
	elsif ($clause) {
		# A directive inside the current clause
		my $d = &make_dir_object($name, $rest, $file, $lnum, $space,
					 $comment, $clause);
		push(@{$clause->{'members'}}, $d);
		if ($file eq $clause->{'file'}) {
			$clause->{'eline'} = $lnum;
			}
		}
	}
return $clause;
}

# make_dir_object(name, value, file, line, space, comment, &clause, [prefix])
sub make_dir_object
{
my ($name, $value, $file, $line, $space, $comment, $clause, $prefix) = @_;
return { 'name' => $name,
	 'value' => $value,
	 'values' => [ &split_values($value) ],
	 'file' => $file,
	 'line' => $line,
	 'space' => $space,
	 'comment' => $comment,
	 'prefix' => $prefix,
	 'clause' => $clause };
}

# split_comment(line)
# Splits a line into the code part and a trailing # comment, honouring quotes
sub split_comment
{
my ($l) = @_;
my $q;
for(my $i=0; $i<length($l); $i++) {
	my $c = substr($l, $i, 1);
	if ($q) {
		$q = undef if ($c eq $q);
		}
	elsif ($c eq '"' || $c eq "'") {
		$q = $c;
		}
	elsif ($c eq '#') {
		return (substr($l, 0, $i), substr($l, $i));
		}
	}
return ($l, undef);
}

# split_values(string)
# Splits a directive value into tokens, removing quotes
sub split_values
{
my ($str) = @_;
my @rv;
while($str =~ /\S/) {
	if ($str =~ /^\s*"([^"]*)"(.*)$/ || $str =~ /^\s*'([^']*)'(.*)$/ ||
	    $str =~ /^\s*(\S+)(.*)$/) {
		push(@rv, $1);
		$str = $2;
		}
	else {
		last;
		}
	}
return @rv;
}

######################################################################
# Finding things
######################################################################

# find_clauses(name, [&conf])
# Returns all clauses with some name, like server or forward-zone
sub find_clauses
{
my ($name, $conf) = @_;
$conf ||= &get_config();
return grep { $_->{'name'} eq $name } @$conf;
}

# find_dirs(name, &clauses)
# Returns all directives with some name in a list of clauses
sub find_dirs
{
my ($name, $clauses) = @_;
return grep { $_->{'name'} eq $name } map { @{$_->{'members'}} } @$clauses;
}

# find_server(name)
# Returns all server: directives with some name
sub find_server
{
my ($name) = @_;
return &find_dirs($name, [ &find_clauses("server") ]);
}

# find_server_value(name)
# Returns the effective (last) value of a single-valued server: directive
sub find_server_value
{
my @d = &find_server(@_);
return @d ? $d[$#d]->{'values'}->[0] : undef;
}

# find_clause_value(name, &clause)
# Returns the last value of a directive in one clause
sub find_clause_value
{
my ($name, $clause) = @_;
my @d = &find_dirs($name, [ $clause ]);
return @d ? $d[$#d]->{'values'}->[0] : undef;
}

# find_clause_values(name, &clause)
# Returns all values of a multi-valued directive in one clause
sub find_clause_values
{
my ($name, $clause) = @_;
return map { $_->{'values'}->[0] } &find_dirs($name, [ $clause ]);
}

# find_zone_clause(type, name)
# Returns the forward-zone, stub-zone or auth-zone clause with some name
sub find_zone_clause
{
my ($type, $name) = @_;
foreach my $c (&find_clauses($type)) {
	my $n = &find_clause_value("name", $c);
	return $c if (&canonical_name($n) eq &canonical_name($name));
	}
return undef;
}

# list_zone_clauses(type)
# Returns hash refs for all forward, stub or auth zones
sub list_zone_clauses
{
my ($type) = @_;
my @rv;
foreach my $c (&find_clauses($type)) {
	my $n = &find_clause_value("name", $c);
	next if (!defined($n));
	push(@rv, { 'name' => $n, 'clause' => $c });
	}
return @rv;
}

# canonical_name(name)
# Lower-cases a domain name and adds a trailing dot
sub canonical_name
{
my ($n) = @_;
$n = lc($n);
$n .= "." if ($n !~ /\.$/);
return $n;
}

# display_name(name)
# Returns a name for showing to the user, without the trailing dot
sub display_name
{
my ($n) = @_;
return $text{'zone_root'} if ($n eq '.');
$n =~ s/\.$//;
return $n;
}

######################################################################
# Writing
######################################################################

# check_raw_value(value)
# Dies if a value would break the config file structure
sub check_raw_value
{
my ($v) = @_;
if ($v =~ /[\r\n\0]/) {
	&error($text{'eraw_newline'});
	}
}

# quote_value(string, [always])
# Quotes a single token if needed (or always)
sub quote_value
{
my ($v, $always) = @_;
&check_raw_value($v);
if (!$always && $v =~ /^[A-Za-z0-9_\-\.\/:@\*]+$/) {
	return $v;
	}
if ($v !~ /"/) {
	return "\"$v\"";
	}
if ($v !~ /'/) {
	return "'$v'";
	}
&error(&text('eraw_quotes', &html_escape($v)));
}

# renumber(file, line, offset)
# Shifts the line numbers of everything in a file at or after some line
sub renumber
{
my ($file, $line, $offset) = @_;
foreach my $c (@{&get_config()}) {
	if ($c->{'file'} eq $file) {
		$c->{'line'} += $offset if ($c->{'line'} >= $line);
		$c->{'eline'} += $offset if ($c->{'eline'} >= $line);
		}
	foreach my $d (@{$c->{'members'}}) {
		next if ($d->{'file'} ne $file);
		$d->{'line'} += $offset if ($d->{'line'} >= $line);
		}
	}
}

# directive_line(&dir, value)
# Returns the text of the config line for a directive
sub directive_line
{
my ($d, $value) = @_;
my $l = ($d->{'prefix'} || $d->{'space'}).$d->{'name'}.": ".$value;
$l .= " ".$d->{'comment'} if ($d->{'comment'});
return $l;
}

# update_directive(&dir, raw-value)
# Changes the value of an existing directive in place
sub update_directive
{
my ($d, $value) = @_;
&check_raw_value($value);
return if ($d->{'value'} eq $value);
my $lref = &read_file_lines($d->{'file'});
$lref->[$d->{'line'}] = &directive_line($d, $value);
$d->{'value'} = $value;
$d->{'values'} = [ &split_values($value) ];
}

# delete_directive(&dir)
# Removes a directive from its file and clause
sub delete_directive
{
my ($d) = @_;
my $lref = &read_file_lines($d->{'file'});
if ($d->{'prefix'}) {
	# Shares a line with the clause header, so keep just the header
	my $p = $d->{'prefix'};
	$p =~ s/\s+$//;
	$lref->[$d->{'line'}] = $p;
	}
else {
	splice(@$lref, $d->{'line'}, 1);
	&renumber($d->{'file'}, $d->{'line'}+1, -1);
	}
my $c = $d->{'clause'};
$c->{'members'} = [ grep { $_ ne $d } @{$c->{'members'}} ];
}

# add_directive(&clause, name, raw-value, [&after-dir])
# Adds a directive to a clause, after some other directive or at the end
sub add_directive
{
my ($c, $name, $value, $after) = @_;
&check_raw_value($value);
my ($file, $line, $space);
if ($after) {
	$file = $after->{'file'};
	$line = $after->{'line'} + 1;
	$space = $after->{'prefix'} ? "\t" : $after->{'space'};
	}
else {
	$file = $c->{'file'};
	$line = $c->{'eline'} + 1;
	my ($last) = reverse(grep { $_->{'file'} eq $file &&
				    !$_->{'prefix'} } @{$c->{'members'}});
	$space = $last ? $last->{'space'} : "\t";
	}
$space = "\t" if ($space eq '');
my $lref = &read_file_lines($file);
&renumber($file, $line, 1);
splice(@$lref, $line, 0, $space.$name.": ".$value);
my $d = &make_dir_object($name, $value, $file, $line, $space, undef, $c);
push(@{$c->{'members'}}, $d);
if ($file eq $c->{'file'} && $line > $c->{'eline'}) {
	$c->{'eline'} = $line;
	}
return $d;
}

# save_directives(&clauses, name, &raw-values, [&clause-for-new])
# Makes a directive in a set of clauses have exactly the given values.
# Existing lines are updated in place, extra ones deleted, and new ones added
# after the last existing one (or at the end of the clause for new).
sub save_directives
{
my ($clauses, $name, $values, $newclause) = @_;
my @old = &find_dirs($name, $clauses);
my $last;
for(my $i=0; $i<@old || $i<@$values; $i++) {
	if ($i < @old && $i < @$values) {
		&update_directive($old[$i], $values->[$i]);
		$last = $old[$i];
		}
	elsif ($i < @old) {
		&delete_directive($old[$i]);
		}
	else {
		my $c = $last ? $last->{'clause'} :
			$newclause || $clauses->[0] || &get_default_server();
		$last = &add_directive($c, $name, $values->[$i], $last);
		}
	}
}

# save_server(name, &raw-values)
# Sets a server: directive to some values (empty list to remove it)
sub save_server
{
my ($name, $values) = @_;
&save_directives([ &find_clauses("server") ], $name, $values,
		 &get_default_server());
}

# get_add_file()
# Returns the file to which new clauses and server: options are added
# The configured file is used if Unbound reads it. Otherwise webmin.conf goes in
# whichever directory the configuration includes, like unbound.conf.d on
# Debian/Ubuntu or conf.d on RHEL/Rocky/Alma/Fedora, so the same module works
# on deb and rpm systems.
sub get_add_file
{
my $f = $config{'add_file'};
$f =~ s/^\s+|\s+$//g;
my @cands = $f ? ( $f ) : ( );
push(@cands, map { $_."/webmin.conf" } &included_conf_dirs());
foreach my $c (&unique(@cands)) {
	next if (!&file_is_included($c));
	if (!-e $c) {
		&lock_file($c);
		&open_tempfile(ADDFILE, ">$c", 0, 1);
		&close_tempfile(ADDFILE);
		&unlock_file($c);
		$change_created{$c} = 1 if ($change_active);
		&clear_config_cache();
		}
	return $c if (&indexof($c, &get_config_files()) >= 0);
	}
return &get_config_file();
}

# file_is_included(file)
# Returns 1 if Unbound reads this file, or would read it once it exists
# because an include: pattern matches it
sub file_is_included
{
my ($f) = @_;
return 1 if (&indexof($f, &get_config_files()) >= 0);
&get_config();
foreach my $g (@config_includes) {
	my $re = quotemeta($g);
	$re =~ s/\\\*/[^\/]*/g;
	$re =~ s/\\\?/[^\/]/g;
	return 1 if ($f =~ /^$re$/);
	}
return 0;
}

# included_conf_dirs()
# Returns directories whose *.conf files the configuration includes
sub included_conf_dirs
{
&get_config();
my @rv;
foreach my $g (@config_includes) {
	push(@rv, $1) if ($g =~ /^(\/.*)\/\*\.conf$/ && -d $1);
	}
return &unique(@rv);
}

# include_conf_dir(dir)
# Adds an include: for dir/*.conf to the end of the main config file
sub include_conf_dir
{
my ($dir) = @_;
my $main = &get_config_file();
&lock_file($main);
my $lref = &read_file_lines($main);
push(@$lref, "include: \"$dir/*.conf\"");
&flush_file_lines($main);
&unlock_file($main);
&clear_config_cache();
}

# get_default_server()
# Returns the server: clause to which new options are added, creating one in
# the add file if needed
sub get_default_server
{
my $f = &get_add_file();
my @servers = &find_clauses("server");
my ($c) = reverse(grep { $_->{'file'} eq $f } @servers);
return $c if ($c);
return &create_clause("server", [ ], $f);
}

# create_clause(name, &[ [name, raw-value], ... ], [file])
# Appends a new clause with some directives to a file. Returns the clause.
sub create_clause
{
my ($name, $dirs, $file) = @_;
$file ||= &get_add_file();
my $lref = &read_file_lines($file);
push(@$lref, "") if (@$lref && $lref->[$#$lref] =~ /\S/);
my $c = { 'type' => 'clause',
	  'name' => $name,
	  'file' => $file,
	  'line' => scalar(@$lref),
	  'eline' => scalar(@$lref),
	  'members' => [ ] };
push(@$lref, $name.":");
foreach my $d (@$dirs) {
	&check_raw_value($d->[1]);
	push(@$lref, "\t".$d->[0].": ".$d->[1]);
	push(@{$c->{'members'}},
	     &make_dir_object($d->[0], $d->[1], $file, $#$lref, "\t",
			      undef, $c));
	$c->{'eline'} = $#$lref;
	}
push(@{&get_config()}, $c);
return $c;
}

# delete_clause(&clause)
# Removes a whole clause from its file
sub delete_clause
{
my ($c) = @_;
# Remove members that live in other (included) files first
foreach my $d (reverse(@{$c->{'members'}})) {
	&delete_directive($d) if ($d->{'file'} ne $c->{'file'});
	}
my $lref = &read_file_lines($c->{'file'});
my ($start, $end) = ($c->{'line'}, $c->{'eline'});
# Also take the blank line before the clause, if there is one
$start-- if ($start > 0 && $lref->[$start-1] !~ /\S/);
my $len = $end - $start + 1;
splice(@$lref, $start, $len);
&renumber($c->{'file'}, $end+1, -$len);
my $conf = &get_config();
@$conf = grep { $_ ne $c } @$conf;
}

######################################################################
# Safe changes: lock, snapshot, write, check, roll back on errors
######################################################################

# begin_change()
# Locks all config files and remembers their contents
sub begin_change
{
$change_active = 1;
%change_backup = ( );
%change_created = ( );
&get_add_file();
foreach my $f (&get_config_files()) {
	&lock_file($f);
	$change_backup{$f} = -e $f ? &read_file_contents($f) : undef;
	}
}

# commit_change([no-check])
# Writes all changes, then runs unbound-checkconf. If it fails, every file is
# put back the way it was and an error is shown.
sub commit_change
{
my ($nocheck) = @_;
&flush_file_lines();
my @files = keys %change_backup;
if (!$nocheck && $config{'check_on_save'} ne '0') {
	my @errs = &check_config();
	if (@errs) {
		&rollback_change();
		&unlock_all_files();
		$change_active = 0;
		&error($text{'echeck_rollback'}."<br>\n<pre>".
		       &html_escape(join("\n", @errs))."</pre>");
		}
	}
&unlock_all_files();
$change_active = 0;
&clear_config_cache();
}

# rollback_change()
# Restores the config files saved by begin_change
sub rollback_change
{
foreach my $f (keys %change_backup) {
	delete($main::file_cache{$f});
	if ($change_created{$f}) {
		&unlink_file($f);
		}
	elsif (defined($change_backup{$f})) {
		&open_tempfile(RESTORE, ">$f", 0, 1);
		&print_tempfile(RESTORE, $change_backup{$f});
		&close_tempfile(RESTORE);
		}
	elsif (-e $f) {
		&unlink_file($f);
		}
	}
&clear_config_cache();
}

######################################################################
# Server control
######################################################################

# get_unbound_version()
# Returns the version number of Unbound, like 1.19.2
sub get_unbound_version
{
if (!defined($unbound_version_cache)) {
	my $out = &backquote_command(
		quotemeta($config{'unbound'})." -V 2>&1 </dev/null");
	$unbound_version_cache = $out =~ /Version\s+([0-9\.]+)/i ? $1 : "";
	}
return $unbound_version_cache;
}

# version_atleast(version)
sub version_atleast
{
my ($want) = @_;
my $ver = &get_unbound_version();
return 0 if (!$ver);
return &compare_version_numbers($ver, $want) >= 0;
}

# check_config()
# Runs unbound-checkconf, returning a list of error lines (empty if OK)
sub check_config
{
return ( ) if (!&has_command($config{'unbound_checkconf'}));
my $out = &backquote_command(
	quotemeta($config{'unbound_checkconf'})." ".
	quotemeta(&get_config_file())." 2>&1 </dev/null");
return ( ) if (!$?);
my @lines = grep { /\S/ } split(/\r?\n/, $out);
return @lines ? @lines : ( "unbound-checkconf failed" );
}

# get_default_value(name)
# Returns the value Unbound uses for an option, via unbound-checkconf -o
sub get_default_value
{
my ($name) = @_;
return undef if (!$config{'show_defaults'});
return undef if (!&has_command($config{'unbound_checkconf'}));
return undef if ($name !~ /^[a-z0-9\-]+$/);
my $out = &backquote_command(
	quotemeta($config{'unbound_checkconf'})." -o ".quotemeta($name)." ".
	quotemeta(&get_config_file())." 2>/dev/null </dev/null");
return undef if ($?);
$out =~ s/\s+$//;
$out =~ s/\n/, /g;
return $out;
}

# get_pid_file()
sub get_pid_file
{
return &find_server_value("pidfile") || $config{'pid_file'};
}

# is_unbound_running()
# Returns the PID of the running server, or 0
sub is_unbound_running
{
my $pid = &check_pid_file(&get_pid_file());
return $pid if ($pid);
# No usable PID file, so look for the process by name. Only trust exact
# matches that are still alive, because kernel threads like
# "kworker/..-events_unbound" and zombie processes also match the name.
return 0 if (!-d "/proc/1");
foreach my $p (&find_byname("unbound")) {
	my $stat = &read_file_contents("/proc/$p/stat");
	next if ($stat !~ /^\d+\s+\((.*)\)\s+(\S)/);
	return $p if ($1 eq "unbound" && $2 ne "Z" && $2 ne "X");
	}
return 0;
}

# control_command(command, [arg, ...])
# Runs unbound-control. Returns (ok, output).
sub control_command
{
my ($cmd, @args) = @_;
return (0, $text{'control_ecmd'})
	if (!&has_command($config{'unbound_control'}));
my $out = &backquote_command(
	quotemeta($config{'unbound_control'})." -c ".
	quotemeta(&get_config_file())." ".
	join(" ", map { quotemeta($_) } ($cmd, @args))." 2>&1 </dev/null");
return ($? ? 0 : 1, $out);
}

# control_available()
# Returns 1 if unbound-control can talk to the running server
sub control_available
{
# Unbound merges all remote-control: clauses, and Fedora has an empty one in
# unbound.conf before the included file that enables it, so the last value
# from any of them counts
my @d = &find_dirs("control-enable", [ &find_clauses("remote-control") ]);
return 0 if (!@d || $d[$#d]->{'values'}->[0] ne "yes");
my ($ok) = &control_command("status");
return $ok;
}

# has_init_script()
sub has_init_script
{
return 0 if (!$config{'init_script'});
&foreign_require("init");
my $st = &init::action_status($config{'init_script'});
return $st ? 1 : 0;
}

# start_unbound()
# Starts the server. Returns undef on success or an error message.
sub start_unbound
{
my @errs = &check_config();
return &text('start_echeck', "<pre>".&html_escape(join("\n", @errs)).
			     "</pre>") if (@errs);
# A process that is still shutting down would make the start a no-op
for(my $i=0; $i<5 && &is_unbound_running(); $i++) {
	sleep(1);
	}
return $text{'start_ealready'} if (&is_unbound_running());
my $cerr = &port_conflict_error();
return $cerr if ($cerr);
my $err = &start_unbound_real();
&forwarder_changed() if (!$err);
return $err;
}

sub start_unbound_real
{
if (&has_init_script()) {
	my ($ok, $out) = &init::start_action($config{'init_script'});
	return "<pre>".&html_escape($out)."</pre>" if (!$ok);
	# The init script can report success even if the server then exits
	for(my $i=0; $i<5 && !&is_unbound_running(); $i++) {
		sleep(1);
		}
	return &is_unbound_running() ? undef :
		&text('start_edied', "<pre>".&html_escape($out)."</pre>").
		&selinux_start_hint();
	}
my $temp = &transname();
&system_logged(quotemeta($config{'unbound'})." -c ".
	       quotemeta(&get_config_file())." >$temp 2>&1 </dev/null");
sleep(1);
my $out = &read_file_contents($temp);
&unlink_file($temp);
return &is_unbound_running() ? undef :
	"<pre>".&html_escape($out)."</pre>".&selinux_start_hint();
}

# selinux_start_hint()
# Returns advice to add to a failed start if SELinux blocks Unbound's port
sub selinux_start_hint
{
my @sp = &selinux_port_problems();
return "" if (!@sp || !defined($sp[0]));
return "<p>".&text('start_eselinux', join("<br>", map {
	"<tt>".&html_escape(&selinux_fix_command($_))."</tt>" } @sp));
}

# stop_unbound()
# Stops the server. Returns undef on success or an error message.
sub stop_unbound
{
if (&has_init_script()) {
	my ($ok, $out) = &init::stop_action($config{'init_script'});
	return "<pre>".&html_escape($out)."</pre>" if (!$ok);
	&wait_for_stop();
	return undef;
	}
my $pid = &is_unbound_running();
return $text{'stop_erunning'} if (!$pid);
&kill_logged('TERM', $pid) || return &text('stop_ekill', $!);
&wait_for_stop();
return undef;
}

# wait_for_stop()
# Waits up to 10 seconds for the server process to really exit, so that a
# following start doesn't find the old one still shutting down
sub wait_for_stop
{
for(my $i=0; $i<10 && &is_unbound_running(); $i++) {
	sleep(1);
	}
}

# restart_needed([set])
# Gets or sets the flag saying that the next apply must fully restart Unbound
sub restart_needed
{
my ($set) = @_;
my $file = "$module_config_directory/restart_needed";
if (defined($set)) {
	if ($set) {
		&open_tempfile(FLAG, ">$file", 0, 1);
		&close_tempfile(FLAG);
		}
	else {
		&unlink_file($file);
		}
	}
return -e $file ? 1 : 0;
}

# apply_configuration()
# Checks the config, then makes the running server load it. Returns undef on
# success or an error message.
sub apply_configuration
{
my $err = &apply_configuration_real();
&forwarder_changed() if (!$err);
return $err;
}

sub apply_configuration_real
{
my @errs = &check_config();
return &text('apply_echeck', "<pre>".&html_escape(join("\n", @errs)).
			     "</pre>") if (@errs);
my $pid = &is_unbound_running();
return $text{'stop_erunning'} if (!$pid);
# A reload or restart onto addresses taken by another program (like Pi-hole
# on port 53) would leave Unbound stopped
my $cerr = &port_conflict_error();
return $cerr if ($cerr);
if (&restart_needed()) {
	# Some changes (like RPZ options) are only picked up by a full restart
	my $err;
	if (&has_init_script()) {
		my ($ok, $out) = &init::restart_action($config{'init_script'});
		$err = $ok ? undef : "<pre>".&html_escape($out)."</pre>";
		}
	else {
		$err = &stop_unbound() || &start_unbound();
		}
	&restart_needed(0) if (!$err);
	return $err;
	}
if ($config{'apply_mode'} ne 'restart' && &control_available()) {
	my $cmd = $config{'apply_mode'} eq 'keep' &&
		  &version_atleast("1.18.0") ? "reload_keep_cache" : "reload";
	my ($ok, $out) = &control_command($cmd);
	return $ok ? undef : "<pre>".&html_escape($out)."</pre>";
	}
if (&has_init_script()) {
	my ($ok, $out) = &init::restart_action($config{'init_script'});
	return $ok ? undef : "<pre>".&html_escape($out)."</pre>";
	}
return &kill_logged('HUP', $pid) ? undef : &text('apply_ehup', $!);
}

######################################################################
# Validation helpers
######################################################################

# valid_domain(name)
# Returns 1 if a string looks like a domain name (trailing dot allowed)
sub valid_domain
{
my ($n) = @_;
return 1 if ($n eq '.');
return $n =~ /^(\*\.)?([A-Za-z0-9_]([A-Za-z0-9_\-]*[A-Za-z0-9_])?\.)*[A-Za-z0-9_]([A-Za-z0-9_\-]*[A-Za-z0-9_])?\.?$/ && length($n) <= 254;
}

# valid_ip(ip)
sub valid_ip
{
my ($ip) = @_;
return &check_ipaddress($ip) || &valid_ip6($ip);
}

# valid_ip6(ip)
# Webmin's check_ip6address accepts strings like "bad" (all hex digits), so
# also require at least one colon
sub valid_ip6
{
my ($ip) = @_;
return $ip =~ /:/ && &check_ip6address($ip);
}

# valid_netblock(net)
# Accepts an address or address/prefix
sub valid_netblock
{
my ($n) = @_;
my ($ip, $len) = split(/\//, $n, 2);
return 0 if (!&valid_ip($ip));
return 1 if (!defined($len));
return 0 if ($len !~ /^\d+$/);
return &check_ipaddress($ip) ? $len <= 32 : $len <= 128;
}

# valid_server_addr(addr)
# Checks an address for forward-addr / stub-addr / primary, which may be
# IP, IP@port, and for TLS IP@port#authname
sub valid_server_addr
{
my ($a) = @_;
my ($ip, $port, $auth);
if ($a =~ /^([^@#]+)(@(\d+))?(#([A-Za-z0-9\.\-_]+))?$/) {
	($ip, $port, $auth) = ($1, $3, $5);
	}
else {
	return 0;
	}
return 0 if (!&valid_ip($ip));
return 0 if (defined($port) && ($port < 1 || $port > 65535));
return 1;
}

# valid_interface(iface)
# Accepts IP, IP@port or an interface name
sub valid_interface
{
my ($i) = @_;
my ($addr, $port) = split(/\@/, $i, 2);
return 0 if (defined($port) && ($port !~ /^\d+$/ || $port > 65535));
return &valid_ip($addr) || $addr =~ /^[A-Za-z][A-Za-z0-9\.\-_]*$/;
}

######################################################################
# Local zones and records
######################################################################

# list_local_zones()
# Returns hash refs for all local-zone: entries
sub list_local_zones
{
my @rv;
foreach my $d (&find_server("local-zone")) {
	my ($name, $type) = @{$d->{'values'}};
	push(@rv, { 'name' => $name,
		    'type' => $type,
		    'dir' => $d });
	}
return @rv;
}

# find_local_zone(name)
sub find_local_zone
{
my ($name) = @_;
my ($z) = grep { &canonical_name($_->{'name'}) eq &canonical_name($name) }
	       &list_local_zones();
return $z;
}

# parse_rr(string)
# Splits an RR string like "www.example.com. 300 IN A 1.2.3.4" into parts
sub parse_rr
{
my ($str) = @_;
my @w;
my $s = $str;
while($s =~ /^\s*("(?:[^"\\]|\\.)*"|\S+)(.*)$/) {
	push(@w, $1);
	$s = $2;
	}
my $rr = { 'name' => shift(@w) };
if (@w && $w[0] =~ /^\d+$/) {
	$rr->{'ttl'} = shift(@w);
	}
if (@w && $w[0] =~ /^(IN|CH|HS|CS)$/i) {
	$rr->{'class'} = uc(shift(@w));
	}
if (@w && $w[0] =~ /^\d+$/ && !defined($rr->{'ttl'})) {
	$rr->{'ttl'} = shift(@w);
	}
$rr->{'type'} = uc(shift(@w));
$rr->{'values'} = \@w;
$rr->{'data'} = join(" ", @w);
return $rr;
}

# list_local_records()
# Returns hash refs for all local-data: and local-data-ptr: entries
sub list_local_records
{
my @rv;
foreach my $d (&find_server("local-data")) {
	my $rr = &parse_rr($d->{'values'}->[0]);
	$rr->{'dir'} = $d;
	push(@rv, $rr);
	}
foreach my $d (&find_server("local-data-ptr")) {
	my ($ip, $host, $ttl);
	my @w = split(/\s+/, $d->{'values'}->[0]);
	($ip, $ttl, $host) = @w == 3 ? @w : ($w[0], undef, $w[1]);
	push(@rv, { 'name' => $host,
		    'type' => 'REVPTR',
		    'ttl' => $ttl,
		    'ip' => $ip,
		    'data' => $ip,
		    'values' => [ $ip ],
		    'dir' => $d });
	}
return @rv;
}

# record_zone(&record, &zones)
# Returns the name of the local zone a record belongs to, or undef
sub record_zone
{
my ($r, $zones) = @_;
my $n = &canonical_name($r->{'name'});
my $best;
foreach my $z (@$zones) {
	my $zn = &canonical_name($z->{'name'});
	if ($zn eq '.' || $n eq $zn || $n =~ /\.\Q$zn\E$/) {
		if (!$best || length($zn) > length(&canonical_name($best))) {
			$best = $z->{'name'};
			}
		}
	}
return $best;
}

# records_for_zone(zone-name|undef)
# Returns records in some zone, or those in no zone if undef
sub records_for_zone
{
my ($zname) = @_;
my @zones = &list_local_zones();
my @rv;
foreach my $r (&list_local_records()) {
	my $z = &record_zone($r, \@zones);
	if (defined($zname) ? defined($z) && &canonical_name($z) eq
					     &canonical_name($zname)
			    : !defined($z)) {
		push(@rv, $r);
		}
	}
return @rv;
}

# record_id(&record)
# Returns an ID that identifies a record directive in a form
sub record_id
{
my ($r) = @_;
return $r->{'dir'}->{'file'}.":".$r->{'dir'}->{'line'};
}

# find_record_by_id(id, old-value)
# Finds a record directive, checking that it has not changed since the form
# was shown
sub find_record_by_id
{
my ($id, $old) = @_;
foreach my $r (&list_local_records()) {
	if (&record_id($r) eq $id && $r->{'dir'}->{'value'} eq $old) {
		return $r;
		}
	}
return undef;
}

# full_record_name(name, zone)
# Converts a name relative to a zone into a full name with trailing dot
sub full_record_name
{
my ($name, $zone) = @_;
$zone = &canonical_name($zone);
if ($name eq '' || $name eq '@') {
	return $zone;
	}
elsif ($name =~ /\.$/) {
	return lc($name);
	}
elsif ($zone eq '.') {
	return lc($name).".";
	}
else {
	return lc($name).".".$zone;
	}
}

# relative_record_name(name, zone)
sub relative_record_name
{
my ($name, $zone) = @_;
my $n = &canonical_name($name);
my $z = &canonical_name($zone);
return '@' if ($n eq $z);
return $n if ($z eq '.');
$n =~ s/\.\Q$z\E$//;
return $n;
}

# txt_strings(text)
# Converts free text into one or more quoted DNS character strings
sub txt_strings
{
my ($t) = @_;
$t =~ s/\\/\\\\/g;
$t =~ s/"/\\"/g;
my @parts;
while(length($t) > 255) {
	my $p = substr($t, 0, 255);
	# Don't split in the middle of an escape
	$p =~ s/\\$//;
	push(@parts, $p);
	$t = substr($t, length($p));
	}
push(@parts, $t);
return join(" ", map { "\"$_\"" } @parts);
}

# txt_unquote(data)
# Converts quoted DNS character strings back into plain text
sub txt_unquote
{
my ($d) = @_;
my $rv = "";
while($d =~ /^\s*"((?:[^"\\]|\\.)*)"(.*)$/) {
	my $p = $1;
	$d = $2;
	$p =~ s/\\(.)/$1/g;
	$rv .= $p;
	}
$rv .= $d if ($rv eq "");
return $rv;
}

# local_data_value(name, ttl, type, data)
# Builds the quoted value for a local-data: line
sub local_data_value
{
my ($name, $ttl, $type, $data) = @_;
my $rr = $name.($ttl ne '' ? " ".$ttl : "")." IN ".$type." ".$data;
&check_raw_value($rr);
if ($rr !~ /"/) {
	return "\"$rr\"";
	}
elsif ($rr !~ /'/) {
	return "'$rr'";
	}
&error($text{'record_equote'});
}

# local_data_ptr_value(ip, name, ttl)
sub local_data_ptr_value
{
my ($ip, $name, $ttl) = @_;
return "\"".$ip.($ttl ne '' ? " ".$ttl : "")." ".$name."\"";
}

######################################################################
# Misc UI helpers
######################################################################

# yesno_input(name, current, default-label)
sub yesno_input
{
my ($name, $value, $deflabel) = @_;
$value = "" if (!defined($value));
return &ui_radio($name, $value eq 'yes' ? 'yes' : $value eq 'no' ? 'no' : '',
		 [ [ '', $deflabel || $text{'default'} ],
		   [ 'yes', $text{'yes'} ],
		   [ 'no', $text{'no'} ] ]);
}

# default_label(option-name)
# Returns "Default" or "Default (value)" for an option
sub default_label
{
my ($name) = @_;
my $def = &get_default_value($name);
return defined($def) && $def ne ''
	? &text('default_val', &html_escape($def)) : $text{'default'};
}

# zone_types_select(name, value)
sub zone_types_select
{
my ($name, $value) = @_;
return &ui_select($name, $value || "static",
	[ map { [ $_, $_." - ".($text{'ztype_'.$_} || $_) ] }
	      @local_zone_types ], 1, 0, 1);
}

# load_pihole_lib()
# Loads the Pi-hole functions, also when called from another module
sub load_pihole_lib
{
return if (defined(&pihole_installed));
my $dir = __FILE__;
$dir =~ s/\/[^\/]+$//;
$dir = "." if ($dir !~ /\//);
do "$dir/pihole-lib.pl";
}

# can_edit(feature)
# Returns 1 if the current Webmin user may use some feature
sub can_edit
{
my ($f) = @_;
# Users from before the Pi-hole pages existed get them with apply rights
return $access{'apply'} ? 1 : 0 if ($f eq 'pihole' && !defined($access{$f}));
return $access{$f} ? 1 : 0;
}

# option_pages()
# Returns the definitions of the global option pages, as a hash of page name
# to clause name and list of [ option, type, extra ]
sub option_pages
{
return (
  'net' => [ 'server',
	[ 'interface', 'multi', 'interface' ],
	[ 'port', 'port' ],
	[ 'do-ip4', 'yesno' ],
	[ 'do-ip6', 'yesno' ],
	[ 'do-udp', 'yesno' ],
	[ 'do-tcp', 'yesno' ],
	[ 'prefer-ip6', 'yesno' ],
	[ 'outgoing-interface', 'multi', 'ip' ],
	[ 'tls-upstream', 'yesno' ],
	[ 'tls-cert-bundle', 'file' ],
	[ 'tls-port', 'port' ],
	[ 'tls-service-key', 'file' ],
	[ 'tls-service-pem', 'file' ],
	],
  'perf' => [ 'server',
	[ 'num-threads', 'int' ],
	[ 'msg-cache-size', 'size' ],
	[ 'rrset-cache-size', 'size' ],
	[ 'key-cache-size', 'size' ],
	[ 'cache-min-ttl', 'int' ],
	[ 'cache-max-ttl', 'int' ],
	[ 'cache-max-negative-ttl', 'int' ],
	[ 'prefetch', 'yesno' ],
	[ 'prefetch-key', 'yesno' ],
	[ 'serve-expired', 'yesno' ],
	[ 'serve-expired-ttl', 'int' ],
	[ 'so-reuseport', 'yesno' ],
	[ 'outgoing-range', 'int' ],
	[ 'num-queries-per-thread', 'int' ],
	[ 'so-rcvbuf', 'size' ],
	[ 'so-sndbuf', 'size' ],
	[ 'edns-buffer-size', 'int' ],
	],
  'sec' => [ 'server',
	[ 'hide-identity', 'yesno' ],
	[ 'hide-version', 'yesno' ],
	[ 'identity', 'text' ],
	[ 'qname-minimisation', 'yesno' ],
	[ 'harden-glue', 'yesno' ],
	[ 'harden-dnssec-stripped', 'yesno' ],
	[ 'harden-below-nxdomain', 'yesno' ],
	[ 'harden-referral-path', 'yesno' ],
	[ 'use-caps-for-id', 'yesno' ],
	[ 'aggressive-nsec', 'yesno' ],
	[ 'deny-any', 'yesno' ],
	[ 'minimal-responses', 'yesno' ],
	[ 'auto-trust-anchor-file', 'file' ],
	[ 'val-permissive-mode', 'yesno' ],
	[ 'domain-insecure', 'multi', 'domain' ],
	[ 'private-address', 'multi', 'netblock' ],
	[ 'private-domain', 'multi', 'domain' ],
	[ 'unwanted-reply-threshold', 'int' ],
	[ 'ratelimit', 'int' ],
	[ 'ip-ratelimit', 'int' ],
	],
  'log' => [ 'server',
	[ 'verbosity', 'select', [ 0 .. 5 ] ],
	[ 'use-syslog', 'yesno' ],
	[ 'logfile', 'file' ],
	[ 'log-time-ascii', 'yesno' ],
	[ 'log-queries', 'yesno' ],
	[ 'log-replies', 'yesno' ],
	[ 'log-servfail', 'yesno' ],
	[ 'log-local-actions', 'yesno' ],
	[ 'val-log-level', 'select', [ 0 .. 2 ] ],
	[ 'statistics-interval', 'int' ],
	[ 'statistics-cumulative', 'yesno' ],
	[ 'extended-statistics', 'yesno' ],
	],
  'rc' => [ 'remote-control',
	[ 'control-enable', 'yesno' ],
	[ 'control-interface', 'multi', 'path' ],
	[ 'control-port', 'port' ],
	[ 'control-use-cert', 'yesno' ],
	[ 'server-key-file', 'file' ],
	[ 'server-cert-file', 'file' ],
	[ 'control-key-file', 'file' ],
	[ 'control-cert-file', 'file' ],
	],
  );
}

######################################################################
# Statistics, test queries and diagnostics
######################################################################

# get_stats()
# Returns a hash of unbound-control stats_noreset values
sub get_stats
{
my ($ok, $out) = &control_command("stats_noreset");
return ( ) if (!$ok);
my %st;
foreach my $l (split(/\r?\n/, $out)) {
	$st{$1} = $2 if ($l =~ /^(\S+)=(\S+)$/);
	}
return %st;
}

# nice_duration(seconds)
# Returns a duration like "3d 4h 12m"
sub nice_duration
{
my ($s) = @_;
return "-" if ($s eq '');
$s = int($s);
my $d = int($s / 86400);
my $h = int(($s % 86400) / 3600);
my $m = int(($s % 3600) / 60);
return $d ? "${d}d ${h}h ${m}m" : $h ? "${h}h ${m}m" : $m ? "${m}m" : "${s}s";
}

# test_query(server, name, type)
# Sends one DNS query with dig. Returns (ok, &answers, error)
sub test_query
{
my ($server, $name, $type) = @_;
return (0, [ ], $text{'monitor_nodig'}) if (!&has_command("dig"));
my $port = &find_server_value("port") || 53;
my $out = &backquote_command(
	"dig +time=3 +tries=1 +noall +answer +comments -p ".quotemeta($port).
	" \@".quotemeta($server)." ".quotemeta($name)." ".quotemeta($type).
	" 2>&1 </dev/null");
if ($? || $out !~ /status:\s*(\S+?),/) {
	$out =~ s/\s+$//;
	return (0, [ ], &text('monitor_failed', &html_escape($out)));
	}
my $status = $1;
if ($status ne 'NOERROR') {
	return (0, [ ], &text('monitor_status', $status));
	}
my @ans;
foreach my $l (split(/\r?\n/, $out)) {
	next if ($l =~ /^;/ || $l !~ /\S/);
	my @w = split(/\s+/, $l);
	push(@ans, join(" ", @w[4..$#w])) if (@w >= 5);
	}
return (0, [ ], $text{'monitor_noanswer'}) if (!@ans);
return (1, \@ans, undef);
}

# port_listeners(port)
# Returns a list of [ proto, address, process ] listening on a port
sub port_listeners
{
my ($port) = @_;
my @rv;
if (&has_command("ss")) {
	my $out = &backquote_command("ss -H -lnptu 2>/dev/null </dev/null");
	foreach my $l (split(/\r?\n/, $out)) {
		my @w = split(/\s+/, $l);
		next if (@w < 5);
		next if ($w[4] !~ /:(\d+)$/ || $1 != $port);
		my ($proc, $pid) = $l =~ /users:\(\("([^"]+)",pid=(\d+)/;
		push(@rv, [ $w[0], $w[4], $proc || "?", $pid ]);
		}
	}
return @rv;
}

# split_listen_addr(ss-address)
# Turns an address from ss like 127.0.0.1:53, [::]:53, *:53 or
# 127.0.0.1%lo:53 into just the IP address
sub split_listen_addr
{
my ($a) = @_;
$a =~ s/:\d+$//;
$a =~ s/^\[(.*)\]$/$1/;
$a =~ s/%\S+$//;
return $a;
}

# addr_overlap(addr1, addr2)
# Returns 1 if two listening addresses would clash. A wildcard address
# clashes with every address of the same family.
sub addr_overlap
{
my ($a, $b) = @_;
return 1 if ($a eq '*' || $b eq '*' || $a eq $b);
my $a6 = $a =~ /:/ ? 1 : 0;
my $b6 = $b =~ /:/ ? 1 : 0;
return 0 if ($a6 != $b6);
my $any = $a6 ? qr/^(::|::0)$/ : qr/^0\.0\.0\.0$/;
return $a =~ $any || $b =~ $any ? 1 : 0;
}

# config_listen_addrs()
# Returns [ address, port ] pairs that the configuration tells Unbound to
# listen on. Interfaces given by name are skipped.
sub config_listen_addrs
{
my $port = &find_server_value("port") || 53;
my @ifaces = map { $_->{'values'}->[0] } &find_server("interface");
@ifaces = ( "127.0.0.1", "::1" ) if (!@ifaces);
my @rv;
foreach my $i (@ifaces) {
	my ($a, $p) = $i =~ /^(.*)\@(\d+)$/ ? ($1, $2) : ($i, $port);
	next if (!&check_ipaddress($a) && !&valid_ip6($a));
	push(@rv, [ $a, $p ]);
	}
return @rv;
}

# port_conflicts()
# Returns listeners of other programs (like Pi-hole) on the addresses and
# ports that the configuration gives to Unbound. Unbound can't start while
# any of these exist.
sub port_conflicts
{
my @rv;
my %done;
foreach my $la (&config_listen_addrs()) {
	foreach my $l (&port_listeners($la->[1])) {
		next if ($l->[2] eq 'unbound' || $l->[2] eq '?');
		next if ($done{$l->[1]."/".$l->[0]}++);
		push(@rv, $l) if (&addr_overlap(&split_listen_addr($l->[1]),
						$la->[0]));
		}
	}
return @rv;
}

# dns_forwarder()
# Looks for a DNS forwarder on port 53 that sends queries on to Unbound,
# like Pi-hole (pihole-FTL) or dnsmasq. Only reads their config files.
# Returns undef if there is none, or a hash ref with keys name, proc, pid,
# upstreams (all of them) and to_unbound (those that point at Unbound).
sub dns_forwarder
{
return $dns_forwarder_cache if (defined($dns_forwarder_cache));
my %fw;
foreach my $l (&port_listeners(53)) {
	if ($l->[2] =~ /^(pihole-FTL|dnsmasq)$/) {
		$fw{'proc'} = $l->[2];
		$fw{'pid'} = $l->[3];
		last;
		}
	}
my $pihole = -d "/etc/pihole" || $fw{'proc'} eq 'pihole-FTL';
if (!$fw{'proc'} && !$pihole) {
	$dns_forwarder_cache = 0;
	return undef;
	}
$fw{'name'} = $pihole ? "Pi-hole" : "dnsmasq";

# Find where the forwarder sends queries
my @up;
my $toml = &read_file_contents("/etc/pihole/pihole.toml");
if ($toml =~ /^\s*upstreams\s*=\s*\[(.*?)\]/ms) {
	# Pi-hole 6
	my $list = $1;
	# Remove comments, but not the # inside values like "127.0.0.1#5335"
	$list =~ s/^((?:[^"#\n]|"[^"\n]*")*)#.*$/$1/mg;
	push(@up, $1) while ($list =~ /"([^"]+)"/g);
	}
if (!@up) {
	# Plain dnsmasq
	my @files = ( "/etc/dnsmasq.conf",
		      glob("/etc/dnsmasq.d/*.conf"),
		      glob("/etc/dnsmasq.d/*[0-9a-z]") );
	foreach my $f (&unique(@files)) {
		next if (!-r $f);
		foreach my $l (split(/\r?\n/, &read_file_contents($f))) {
			# Only servers for all domains, not server=/dom/ip
			push(@up, $1) if ($l =~ /^\s*server\s*=\s*([^\/\s]\S*)/);
			}
		}
	}

# Which of them are Unbound?
my @mine = &config_listen_addrs();
my @to;
foreach my $u (&unique(@up)) {
	my ($a, $p) = $u =~ /^(.*)#(\d+)$/ ? ($1, $2) : ($u, 53);
	$a =~ s/^\[(.*)\]$/$1/;
	# Either the running server or the configuration listens there
	my @live = map { [ &split_listen_addr($_->[1]), $p ] }
		       grep { $_->[2] eq 'unbound' } &port_listeners($p);
	push(@to, $u) if (grep { $_->[1] == $p &&
				 &addr_overlap($_->[0], $a) } (@mine, @live));
	}
$fw{'upstreams'} = [ &unique(@up) ];
$fw{'to_unbound'} = \@to;
$dns_forwarder_cache = \%fw;
return \%fw;
}

# net_contains(netblock, ip)
# Returns 1 if an IP address is inside a netblock like 10.0.0.0/8
sub net_contains
{
my ($net, $ip) = @_;
my ($na, $bits) = split(/\//, $net, 2);
eval "use Socket qw(inet_pton AF_INET AF_INET6)";
return 0 if ($@);
my $fam = $na =~ /:/ ? &AF_INET6 : &AF_INET;
return 0 if (($ip =~ /:/ ? &AF_INET6 : &AF_INET) != $fam);
my $nb = &inet_pton($fam, $na);
my $ib = &inet_pton($fam, $ip);
return 0 if (!defined($nb) || !defined($ib));
$bits = length($nb) * 8 if ($bits eq '');
my $nbits = unpack("B*", $nb);
my $ibits = unpack("B*", $ib);
return substr($nbits, 0, $bits) eq substr($ibits, 0, $bits) ? 1 : 0;
}

# access_action(ip)
# Returns the access-control action Unbound applies to queries from an IP
sub access_action
{
my ($ip) = @_;
my ($best, $bestlen) = (undef, -1);
foreach my $d (&find_server("access-control")) {
	my ($net, $act) = @{$d->{'values'}};
	$net .= ($net =~ /:/ ? "/128" : "/32") if ($net !~ /\//);
	my ($len) = $net =~ /\/(\d+)$/;
	if (&net_contains($net, $ip) && $len >= $bestlen) {
		($best, $bestlen) = ($act, $len);
		}
	}
return $best if (defined($best));
# Unbound's built-in default only allows the local host
return $ip eq '::1' || $ip =~ /^127\./ ? "allow" : "refuse";
}

# forwarder_problems()
# Returns messages describing how the current configuration would break a
# forwarder (like Pi-hole) that uses Unbound, once applied
sub forwarder_problems
{
my $fw = &dns_forwarder();
return ( ) if (!$fw);
my @rv;
my @mine = &config_listen_addrs();
my @used;
foreach my $u (@{$fw->{'upstreams'}}) {
	my ($a, $p) = $u =~ /^(.*)#(\d+)$/ ? ($1, $2) : ($u, 53);
	$a =~ s/^\[(.*)\]$/$1/;
	next if (!&check_ipaddress($a) && !&valid_ip6($a));
	# Only check upstreams on this host
	next if ($a !~ /^127\./ && $a ne '::1' &&
		 !grep { $_->[0] eq $a } @mine);
	push(@used, $u);
	if (!grep { $_->[1] == $p && &addr_overlap($_->[0], $a) } @mine) {
		push(@rv, &text('fwd_enolisten', $fw->{'name'},
				&html_escape($u)));
		}
	elsif ($a =~ /^127\./ || $a eq '::1') {
		my $act = &access_action($a);
		if ($act !~ /^allow/) {
			push(@rv, &text('fwd_eaccess', $fw->{'name'},
					&html_escape($a), &html_escape($act)));
			}
		}
	}
return @rv;
}

# port_conflict_error()
# Returns an error message if other programs hold the addresses and ports
# that Unbound is configured to use, or undef
sub port_conflict_error
{
my @c = &port_conflicts();
return undef if (!@c);
return &text('start_eport', join(", ", map {
	"<tt>".&html_escape($_->[2])."</tt> (".&html_escape($_->[0]." ".
	$_->[1]).")" } @c));
}

# private_ip(server-address)
# Returns 1 if a server address like 192.168.1.1@53#name is on a private,
# local or link-local network
sub private_ip
{
my ($a) = @_;
$a =~ s/[@#].*$//;
foreach my $n ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
	       "127.0.0.0/8", "169.254.0.0/16", "100.64.0.0/10",
	       "fc00::/7", "fe80::/10", "::1/128") {
	return 1 if (&net_contains($n, $a));
	}
return 0;
}

# domain_listed(directive, name)
# Returns 1 if a server directive like private-domain lists a domain or one
# of its parents
sub domain_listed
{
my ($dname, $name) = @_;
my $n = &canonical_name($name);
foreach my $d (&find_server($dname)) {
	my $v = &canonical_name($d->{'values'}->[0]);
	return 1 if ($v eq '.' || $n eq $v || $n =~ /\.\Q$v\E$/);
	}
return 0;
}

# set_domain_listed(directive, name, on)
# Adds or removes a domain in a server directive like private-domain
sub set_domain_listed
{
my ($dname, $name, $on) = @_;
my $n = &canonical_name($name);
my @old = &find_server($dname);
my @keep = grep { &canonical_name($_->{'values'}->[0]) ne $n } @old;
my @vals = map { $_->{'value'} } @keep;
push(@vals, &quote_value(&display_name($n), 1)) if ($on);
return if (!$on && @keep == @old);
return if ($on && @keep != @old);
&save_server($dname, \@vals);
}

# private_zone_problems()
# Returns forward and stub zones whose servers are private but whose
# answers would have their private addresses removed by private-address
sub private_zone_problems
{
return ( ) if (!&find_server("private-address"));
my @rv;
foreach my $t ("forward", "stub") {
	foreach my $z (&list_zone_clauses($t."-zone")) {
		my $c = $z->{'clause'};
		my $n = &canonical_name($z->{'name'});
		next if ($n eq '.');
		my @addrs = &find_clause_values($t."-addr", $c);
		next if (!grep { &private_ip($_) } @addrs);
		push(@rv, $n) if (!&domain_listed("private-domain", $n));
		}
	}
return @rv;
}

# apparmor_allowed(path, write)
# Returns 1 if the AppArmor profile for Unbound allows a path, 0 if not, or
# undef if there is no profile
sub apparmor_allowed
{
my ($path, $write) = @_;
my $prof = "/etc/apparmor.d/usr.sbin.unbound";
return undef if (!-r $prof);
foreach my $f ($prof, "/etc/apparmor.d/local/usr.sbin.unbound") {
	foreach my $l (split(/\r?\n/, &read_file_contents($f))) {
		next if ($l =~ /^\s*(#|audit\s+deny|deny)/);
		next if ($l !~ /^\s*(?:owner\s+)?(\/\S+)\s+([a-z]+)\s*,/);
		my ($glob, $perm) = ($1, $2);
		next if ($write && $perm !~ /w/);
		next if (!$write && $perm !~ /r/);
		my $re = quotemeta($glob);
		$re =~ s/\\\{(.*?)\\\}/"(?:".join("|", split(m{\\,}, $1)).")"/ge;
		$re =~ s/\\\*\\\*/.*/g;
		$re =~ s/\\\*/[^\/]*/g;
		return 1 if ($path =~ /^$re$/);
		}
	}
return 0;
}

# apparmor_problems()
# Returns [ path, why ] for files Unbound must write that its AppArmor
# profile doesn't allow
sub apparmor_problems
{
my @need;
my $log = &find_server_value("logfile");
push(@need, [ $log, 'log' ]) if ($log =~ /^\//);
foreach my $t ("rpz", "auth-zone") {
	foreach my $z (&list_zone_clauses($t)) {
		my $c = $z->{'clause'};
		my $zf = &find_clause_value("zonefile", $c);
		next if ($zf !~ /^\//);
		# Unbound only writes the file when it downloads the zone
		next if (!&find_clause_values("url", $c) &&
			 !&find_clause_values("primary", $c) &&
			 !&find_clause_values("master", $c));
		push(@need, [ $zf, 'zone', &canonical_name($z->{'name'}) ]);
		}
	}
my @rv;
foreach my $n (@need) {
	my $ok = &apparmor_allowed($n->[0], 1);
	return ( ) if (!defined($ok));
	push(@rv, $n) if (!$ok);
	}
return @rv;
}

# selinux_mode()
# Returns enforcing, permissive or undef if SELinux is off or missing
sub selinux_mode
{
my $e = &read_file_contents("/sys/fs/selinux/enforce");
if ($e eq '' && &has_command("getenforce")) {
	my $out = &backquote_command("getenforce 2>/dev/null");
	return $out =~ /enforcing/i ? 'enforcing' :
	       $out =~ /permissive/i ? 'permissive' : undef;
	}
return undef if ($e !~ /^\s*([01])/);
return $1 ? 'enforcing' : 'permissive';
}

# selinux_port_types()
# Returns a hash from "proto/port" to the SELinux type of that port, from
# semanage, or undef if semanage isn't installed
sub selinux_port_types
{
return undef if (!&has_command("semanage"));
my %rv;
foreach my $l (split(/\n/, &backquote_command(
			"semanage port -l 2>/dev/null </dev/null"))) {
	next if ($l !~ /^(\S+)\s+(tcp|udp)\s+(.*)$/);
	my ($type, $proto, $ports) = ($1, $2, $3);
	foreach my $p (split(/\s*,\s*/, $ports)) {
		if ($p =~ /^(\d+)-(\d+)$/) {
			# Ranges are only the generic types, kept apart
			push(@{$rv{'range/'.$proto}}, [ $1, $2, $type ]);
			}
		elsif ($p =~ /^\d+$/) {
			$rv{$proto.'/'.$p} ||= $type;
			}
		}
	}
return \%rv;
}

# selinux_port_problems()
# Returns [ proto, port, current-type ] for each port that the configuration
# gives Unbound but that the SELinux policy doesn't let it bind to. Unbound
# runs as named_t, which can bind dns_port_t, high ephemeral ports and (UDP
# only) unreserved ports. Port 5335 from the Pi-hole guide is howl_port_t on
# RHEL-family systems, so Unbound can't listen on TCP 5335 there.
sub selinux_port_problems
{
return ( ) if (!&selinux_mode());
my $types = &selinux_port_types();
return undef if (!$types);
my %ports = map { $_->[1], 1 } &config_listen_addrs();
my @protos;
push(@protos, 'udp') if (&find_server_value("do-udp") ne 'no');
push(@protos, 'tcp') if (&find_server_value("do-tcp") ne 'no');
my @rv;
foreach my $port (sort { $a <=> $b } keys %ports) {
	foreach my $proto (@protos) {
		my $t = $types->{$proto.'/'.$port};
		if (!$t) {
			foreach my $r (@{$types->{'range/'.$proto} || [ ]}) {
				$t = $r->[2] if ($port >= $r->[0] &&
						 $port <= $r->[1]);
				}
			}
		$t ||= 'port_t';
		next if ($t eq 'dns_port_t' || $t eq 'ephemeral_port_t');
		next if ($proto eq 'udp' && $t eq 'unreserved_port_t');
		push(@rv, [ $proto, $port, $t ]);
		}
	}
return @rv;
}

# selinux_fix_command(&problem)
# Returns the semanage command that lets Unbound use a port
sub selinux_fix_command
{
my ($p) = @_;
my $op = $p->[2] =~ /^(port_t|unreserved_port_t|ephemeral_port_t)$/ ?
		"-a" : "-m";
return "semanage port $op -t dns_port_t -p $p->[0] $p->[1]";
}

# unread_config_files()
# Returns .conf files in the usual Unbound directories that the configuration
# never includes, like a Pi-hole guide file put in unbound.conf.d on a system
# whose unbound.conf only reads conf.d
sub unread_config_files
{
my $main = &get_config_file();
my $dir = $main;
$dir =~ s/\/[^\/]+$//;
my %read = map { $_, 1 } &get_config_files();
foreach my $f (&get_config_files()) {
	my $r = &resolve_links($f);
	$read{$r} = 1 if ($r);
	}
my @rv;
foreach my $sub ("unbound.conf.d", "conf.d", "local.d") {
	next if (!-d "$dir/$sub");
	opendir(my $dh, "$dir/$sub") || next;
	foreach my $f (sort readdir($dh)) {
		next if ($f !~ /\.conf$/);
		my $path = "$dir/$sub/$f";
		next if ($read{$path} || $read{&resolve_links($path)});
		push(@rv, $path);
		}
	closedir($dh);
	}
return @rv;
}

# parse_size(value)
# Converts a size like 1m or 4096 to bytes
sub parse_size
{
my ($v) = @_;
return undef if ($v !~ /^(\d+)\s*([kmg]?)b?$/i);
my %m = ( '' => 1, 'k' => 1024, 'm' => 1024*1024, 'g' => 1024*1024*1024 );
return $1 * $m{lc($2)};
}

# forwarder_changed()
# Called after Unbound's answers change, so that a forwarder like Pi-hole
# doesn't keep serving its cached copies of the old ones
sub forwarder_changed
{
&flush_forwarder();
}

# flush_forwarder()
# Flushes the DNS cache of a forwarder (like Pi-hole) that uses Unbound, by
# sending it SIGHUP. This is what "pihole reloaddns" does; DNS keeps working.
sub flush_forwarder
{
return 0 if (!$config{'forwarder_flush'});
my $fw = &dns_forwarder();
return 0 if (!$fw || !$fw->{'pid'} || !@{$fw->{'to_unbound'}});
return &kill_logged('HUP', $fw->{'pid'}) ? 1 : 0;
}

# get_resolver_status()
# Returns a hash describing /etc/resolv.conf
sub get_resolver_status
{
my %rv;
my $f = "/etc/resolv.conf";
$rv{'link'} = -l $f ? readlink($f) : undef;
$rv{'resolved'} = $rv{'link'} && $rv{'link'} =~ /systemd\/resolve/ ? 1 : 0;
my @ns;
foreach my $l (split(/\r?\n/, &read_file_contents($f))) {
	push(@ns, $1) if ($l =~ /^\s*nameserver\s+(\S+)/);
	}
$rv{'nameservers'} = \@ns;
$rv{'uses_local'} = (grep { $_ eq '127.0.0.1' || $_ eq '::1' } @ns) ? 1 : 0;
return %rv;
}

######################################################################
# Views
######################################################################

# list_views()
# Returns hash refs for all view: clauses
sub list_views
{
return &list_zone_clauses("view");
}

# view_clients(name)
# Returns the access-control-view directives that select a view
sub view_clients
{
my ($name) = @_;
return grep { $_->{'values'}->[1] eq $name ||
	      ($_->{'values'}->[0] =~ /\s/ &&
	       (split(/\s+/, $_->{'values'}->[0]))[1] eq $name) }
	    &find_server("access-control-view");
}

######################################################################
# Live changes through unbound-control
######################################################################

# live_enabled()
# Returns 1 if record changes should also be pushed to the running server
sub live_enabled
{
return 0 if ($config{'live_apply'} eq '0');
return &is_unbound_running() && &control_available();
}

# reverse_name(ip)
# Returns the in-addr.arpa or ip6.arpa name for an address
sub reverse_name
{
my ($ip) = @_;
if (&check_ipaddress($ip)) {
	return join(".", reverse(split(/\./, $ip))).".in-addr.arpa.";
	}
# Expand :: into the right number of zero groups
my ($a, $b) = split(/::/, $ip, 2);
my @a = split(/:/, $a || "");
my @b = split(/:/, $b || "");
my @mid = $ip =~ /::/ ? ("0") x (8 - @a - @b) : ( );
my $full = join(":", @a, @mid, @b);
my $hex = join("", map { sprintf("%04x", hex($_)) } split(/:/, $full));
return join(".", reverse(split(//, $hex))).".ip6.arpa.";
}

# live_sync_names(name, ...)
# Makes the running server's local data for some names match the config
sub live_sync_names
{
my @names = &unique(map { &canonical_name($_) } @_);
return if (!@names || !&live_enabled());
&clear_config_cache();
my @recs = &list_local_records();
foreach my $n (@names) {
	&control_command("local_data_remove", $n);
	foreach my $r (@recs) {
		if ($r->{'type'} eq 'REVPTR') {
			my $rev = &reverse_name($r->{'ip'});
			next if ($rev ne $n);
			&control_command("local_data",
				join(" ", $rev, $r->{'ttl'} ne '' ? $r->{'ttl'} : (),
					  "IN PTR", &canonical_name($r->{'name'})));
			}
		elsif (&canonical_name($r->{'name'}) eq $n) {
			&control_command("local_data", $r->{'dir'}->{'values'}->[0]);
			}
		}
	}
&forwarder_changed();
}

# live_zone(add|remove, name, [type])
sub live_zone
{
my ($action, $name, $type) = @_;
return if (!&live_enabled());
if ($action eq 'add') {
	&control_command("local_zone", &canonical_name($name), $type);
	}
else {
	&control_command("local_zone_remove", &canonical_name($name));
	}
&forwarder_changed();
}

# record_live_names(&record)
# Returns the DNS names whose live data changes with a record
sub record_live_names
{
my ($r) = @_;
return $r->{'type'} eq 'REVPTR' ? ( &reverse_name($r->{'ip'}) )
				 : ( $r->{'name'} );
}

######################################################################
# Batch import
######################################################################

# parse_hosts_lines(text)
# Parses hosts-file format lines into [ ip, name, aliases... ]
sub parse_hosts_lines
{
my ($text) = @_;
my @rv;
foreach my $l (split(/\r?\n/, $text)) {
	$l =~ s/#.*$//;
	my @w = split(/\s+/, $l);
	shift(@w) if (@w && $w[0] eq '');
	next if (@w < 2 || !&valid_ip($w[0]));
	push(@rv, [ @w ]);
	}
return @rv;
}

# list_dhcp_leases()
# Returns [ ip, hostname ] for active leases from ISC dhcpd or Kea
sub list_dhcp_leases
{
my @rv;
my $now = time();
# ISC dhcpd, using the lease file path from its Webmin module if installed
my $isc = "/var/lib/dhcp/dhcpd.leases";
if (&foreign_check("dhcpd")) {
	my %dc = &foreign_config("dhcpd");
	$isc = $dc{'lease_file'} if ($dc{'lease_file'});
	}
if (-r $isc) {
	my $data = &read_file_contents($isc);
	my %byip;
	while($data =~ /lease\s+(\S+)\s*\{(.*?)\n\}/sg) {
		my ($ip, $body) = ($1, $2);
		my ($host) = $body =~ /client-hostname\s+"([^"]+)"/;
		my ($state) = $body =~ /binding state\s+(\w+)/;
		my ($ends) = $body =~ /ends\s+\d+\s+(\d+\/\d+\/\d+ \d+:\d+:\d+)/;
		next if (!$host || ($state && $state ne 'active'));
		if ($ends) {
			my @t = split(/[\/ :]/, $ends);
			my $e = eval { require Time::Local;
				       Time::Local::timegm($t[5], $t[4], $t[3],
						$t[2], $t[1]-1, $t[0]) };
			next if ($e && $e < $now);
			}
		$byip{$ip} = $host;	# later entries win
		}
	push(@rv, map { [ $_, $byip{$_}, "isc" ] } sort keys %byip);
	}
# Kea DHCPv4 memfile leases
foreach my $kea ("/var/lib/kea/kea-leases4.csv", "/var/lib/kea/dhcp4.leases") {
	next if (!-r $kea);
	my %byip;
	foreach my $l (split(/\r?\n/, &read_file_contents($kea))) {
		my @c = split(/,/, $l);
		next if ($c[0] !~ /^\d+\.\d+\.\d+\.\d+$/);
		next if ($c[4] && $c[4] < $now);
		next if (!$c[8]);
		$byip{$c[0]} = $c[8];
		}
	push(@rv, map { [ $_, $byip{$_}, "kea" ] } sort keys %byip);
	}
# Pi-hole and dnsmasq : expiry mac ip hostname client-id
foreach my $dm ("/etc/pihole/dhcp.leases", "/var/lib/misc/dnsmasq.leases") {
	next if (!-r $dm);
	my %byip;
	foreach my $l (split(/\r?\n/, &read_file_contents($dm))) {
		my @c = split(/\s+/, $l);
		next if (@c < 4 || $c[2] !~ /^\d+\.\d+\.\d+\.\d+$/);
		next if ($c[0] && $c[0] < $now);
		next if ($c[3] eq '*' || $c[3] eq '');
		$byip{$c[2]} = $c[3];
		}
	push(@rv, map { [ $_, $byip{$_}, $dm =~ /pihole/ ? "pihole" : "dnsmasq" ] }
		  sort keys %byip);
	}
return @rv;
}

# ensure_respip()
# Makes sure module-config includes respip, which RPZ needs. Unbound does not
# accept respip together with subnetcache, so subnetcache is dropped unless
# EDNS Client Subnet is actually configured.
sub ensure_respip
{
my $mc = &find_server_value("module-config");
my $cur = $mc || &get_default_value("module-config") ||
	  "validator iterator";
return if ($cur =~ /\brespip\b/);
my @mods = split(/\s+/, $cur);
if (&indexof("subnetcache", @mods) >= 0) {
	if (&find_server("send-client-subnet") ||
	    &find_server("client-subnet-zone")) {
		&error($text{'rpz_esubnet'});
		}
	@mods = grep { $_ ne "subnetcache" } @mods;
	}
my $i = &indexof("validator", @mods);
$i = &indexof("iterator", @mods) if ($i < 0);
$i = 0 if ($i < 0);
splice(@mods, $i, 0, "respip");
&save_server("module-config", [ "\"".join(" ", @mods)."\"" ]);
}

1;
