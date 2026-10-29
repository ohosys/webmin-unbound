# pihole-lib.pl
# Talks to a local Pi-hole 6 through its REST API. Authenticates with the
# CLI password file that Pi-hole writes for local root tools (the same one the
# "pihole" command uses), so no password has to be stored in Webmin.

our ($pihole_sid, $pihole_open, $pihole_target, $pihole_last_error);
our $pihole_toml = "/etc/pihole/pihole.toml";
our $pihole_clipw = "/etc/pihole/cli_pw";

# pihole_installed()
# Returns 1 if Pi-hole 6 looks installed on this system
sub pihole_installed
{
return -r $pihole_toml && (&has_command("pihole-FTL") || -d "/etc/pihole")
	? 1 : 0;
}

# pihole_toml_value(section, key)
# Returns a simple value from pihole.toml, like webserver / port
sub pihole_toml_value
{
my ($sect, $key) = @_;
my $cur = "";
foreach my $l (split(/\r?\n/, &read_file_contents($pihole_toml))) {
	if ($l =~ /^\s*\[([^\]]+)\]/) {
		$cur = $1;
		next;
		}
	next if ($cur ne $sect);
	if ($l =~ /^\s*\Q$key\E\s*=\s*"([^"]*)"/) {
		return $1;
		}
	if ($l =~ /^\s*\Q$key\E\s*=\s*([^\s#]+)/) {
		return $1;
		}
	}
return undef;
}

# pihole_api_target()
# Returns ( host, port, ssl ) for the local Pi-hole API, from the module
# config or from webserver.port in pihole.toml
sub pihole_api_target
{
return @$pihole_target if ($pihole_target);
my @rv;
if ($config{'pihole_api'} =~ /^(https?):\/\/([A-Za-z0-9\.\-]+|\[[0-9a-fA-F:\.]+\]):(\d+)\/*$/ &&
    &pihole_local_host($2)) {
	@rv = ( $2, $3, $1 eq 'https' ? 1 : 0 );
	}
else {
	# Like "80o,443os,[::]:80o,[::]:443os" : o = optional, s = TLS,
	# r = redirect to TLS
	my $ports = &pihole_toml_value("webserver", "port") ||
		    "80o,443os,[::]:80o,[::]:443os";
	my (@http, @https);
	foreach my $p (split(/\s*,\s*/, $ports)) {
		next if ($p =~ /^\[/);			# IPv6 only
		next if ($p !~ /^(?:([\d\.]+):)?(\d+)([a-z]*)$/);
		my ($ip, $port, $flags) = ($1, $2, $3);
		next if ($ip && $ip ne '127.0.0.1' && $ip ne '0.0.0.0');
		next if ($flags =~ /r/);
		push(@{$flags =~ /s/ ? \@https : \@http}, $port);
		}
	@rv = @http ? ( "127.0.0.1", $http[0], 0 ) :
	      @https ? ( "127.0.0.1", $https[0], 1 ) :
		       ( "127.0.0.1", 80, 0 );
	}
$pihole_target = \@rv;
return @rv;
}

# pihole_local_host(host)
# Returns 1 if a host is this system. The module logs in with Pi-hole's local
# CLI password, which must never be sent to another machine.
sub pihole_local_host
{
my ($h) = @_;
$h =~ s/^\[(.*)\]$/$1/;
return 1 if ($h eq 'localhost' || $h =~ /^127\.\d+\.\d+\.\d+$/ || $h eq '::1');
return 0 if (!&check_ipaddress($h) && !&check_ip6address($h));
&foreign_require("net");
foreach my $i (&net::active_interfaces()) {
	return 1 if ($i->{'address'} && $i->{'address'} eq $h);
	return 1 if (&indexoflc($h, @{$i->{'address6'} || [ ]}) >= 0);
	}
return 0;
}

# pihole_json_module()
# Returns 1 if JSON::XS or JSON::PP is installed. Minimal RHEL-family systems
# often lack them (perl-JSON-PP is a separate package), so the module carries a
# small codec of its own for that case.
our $pihole_json_mod;
sub pihole_json_module
{
$pihole_json_mod = (eval { require JSON::XS; 1 } ||
		    eval { require JSON::PP; 1 }) ? 1 : 0
	if (!defined($pihole_json_mod));
return $pihole_json_mod;
}

# pihole_to_json(&data)
# Encodes data like Webmin's convert_to_json does
sub pihole_to_json
{
my ($data) = @_;
return &convert_to_json($data) if (&pihole_json_module());
return &pihole_json_enc($data);
}

# pihole_from_json(text)
# Decodes UTF-8 JSON text like Webmin's convert_from_json does
sub pihole_from_json
{
my ($text) = @_;
return &convert_from_json($text) if (&pihole_json_module());
utf8::decode($text);
pos($text) = 0;
my $rv = &pihole_json_val(\$text);
$text =~ /\G\s*/gc;
die "Trailing data in JSON\n" if (pos($text) != length($text));
return $rv;
}

sub pihole_json_enc
{
my ($v) = @_;
return "null" if (!defined($v));
my $r = ref($v);
if ($r eq 'HASH') {
	return "{".join(",", map { &pihole_json_str($_).":".
				   &pihole_json_enc($v->{$_}) }
			      sort keys %$v)."}";
	}
if ($r eq 'ARRAY') {
	return "[".join(",", map { &pihole_json_enc($_) } @$v)."]";
	}
return $$v ? "true" : "false" if ($r eq 'SCALAR');
return $v ? "true" : "false" if ($r);
# Same number test as JSON::PP : created as a number, not as a string
if (defined(&builtin::created_as_number)) {
	no warnings;
	return $v if (&builtin::created_as_number($v));
	}
else {
	require B;
	my $f = B::svref_2object(\$v)->FLAGS;
	return $v if ($f & (B::SVp_IOK() | B::SVp_NOK()) &&
		      !($f & B::SVp_POK()));
	}
return &pihole_json_str($v);
}

sub pihole_json_str
{
my ($s) = @_;
$s =~ s/([\\"])/\\$1/g;
$s =~ s/\n/\\n/g;
$s =~ s/\r/\\r/g;
$s =~ s/\t/\\t/g;
$s =~ s/([\x00-\x1f])/sprintf("\\u%04x", ord($1))/ge;
$s =~ s/([^\x00-\xff])/&pihole_json_uesc(ord($1))/ge;
return '"'.$s.'"';
}

sub pihole_json_uesc
{
my ($c) = @_;
return sprintf("\\u%04x", $c) if ($c < 0x10000);
$c -= 0x10000;
return sprintf("\\u%04x\\u%04x", 0xd800 + ($c >> 10), 0xdc00 + ($c & 0x3ff));
}

sub pihole_json_val
{
my ($t) = @_;
$$t =~ /\G\s*/gc;
if ($$t =~ /\G\{/gc) {
	my %h;
	$$t =~ /\G\s*/gc;
	return \%h if ($$t =~ /\G\}/gc);
	while(1) {
		$$t =~ /\G\s*/gc;
		$$t =~ /\G"/gc || die "Expected string in JSON\n";
		my $k = &pihole_json_strval($t);
		$$t =~ /\G\s*:/gc || die "Expected : in JSON\n";
		$h{$k} = &pihole_json_val($t);
		$$t =~ /\G\s*/gc;
		next if ($$t =~ /\G,/gc);
		last if ($$t =~ /\G\}/gc);
		die "Expected , or } in JSON\n";
		}
	return \%h;
	}
if ($$t =~ /\G\[/gc) {
	my @a;
	$$t =~ /\G\s*/gc;
	return \@a if ($$t =~ /\G\]/gc);
	while(1) {
		push(@a, &pihole_json_val($t));
		$$t =~ /\G\s*/gc;
		next if ($$t =~ /\G,/gc);
		last if ($$t =~ /\G\]/gc);
		die "Expected , or ] in JSON\n";
		}
	return \@a;
	}
return &pihole_json_strval($t) if ($$t =~ /\G"/gc);
return 1 if ($$t =~ /\Gtrue/gc);
return 0 if ($$t =~ /\Gfalse/gc);
return undef if ($$t =~ /\Gnull/gc);
return $1+0 if ($$t =~ /\G(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)/gc);
die "Bad JSON value\n";
}

sub pihole_json_strval
{
my ($t) = @_;
my $s = "";
while(1) {
	if ($$t =~ /\G([^"\\]+)/gc) {
		$s .= $1;
		}
	elsif ($$t =~ /\G"/gc) {
		return $s;
		}
	elsif ($$t =~ /\G\\u([0-9a-fA-F]{4})/gc) {
		my $c = hex($1);
		if ($c >= 0xd800 && $c < 0xdc00 &&
		    $$t =~ /\G\\u([dD][c-fC-F][0-9a-fA-F]{2})/gc) {
			$c = 0x10000 + (($c - 0xd800) << 10) + (hex($1) - 0xdc00);
			}
		$s .= chr($c);
		}
	elsif ($$t =~ /\G\\(.)/gcs) {
		my %esc = ( 'n' => "\n", 't' => "\t", 'r' => "\r", 'b' => "\b",
			    'f' => "\f" );
		$s .= exists($esc{$1}) ? $esc{$1} : $1;
		}
	else {
		die "Unterminated string in JSON\n";
		}
	}
}

# pihole_http(method, path, [&body])
# Makes one HTTP request to the API. Returns ( status, decoded-json-or-text,
# error ).
sub pihole_http
{
my ($method, $path, $body) = @_;
my ($host, $port, $ssl) = &pihole_api_target();
my $content = defined($body) ? &pihole_to_json($body) : undef;
my @h = ( [ "Host", $host ], [ "User-agent", "Webmin" ],
	  [ "Accept", "application/json" ], [ "Connection", "close" ] );
push(@h, [ "X-FTL-SID", $pihole_sid ]) if ($pihole_sid);
if (defined($content)) {
	push(@h, [ "Content-type", "application/json" ],
		 [ "Content-length", length($content) ]);
	}
local $SIG{ALRM} = sub { die "timeout\n" };
my ($status, $data, $err);
eval {
	alarm($path =~ /gravity/ ? 900 : 30);
	my $hc = &make_http_connection($host, $port, $ssl, $method,
				       "/api".$path, \@h);
	if (!ref($hc)) {
		$err = $hc;
		alarm(0);
		return;
		}
	&write_http_connection($hc, $content) if (defined($content));
	my $line = &read_http_connection($hc);
	($status) = $line =~ /^HTTP\/\S+\s+(\d+)/;
	my %hdr;
	while(1) {
		$line = &read_http_connection($hc);
		last if (!defined($line));
		$line =~ s/\r?\n$//;
		last if ($line eq "");
		$hdr{lc($1)} = $2 if ($line =~ /^([^:]+):\s*(.*)$/);
		}
	my $raw = "";
	while(defined(my $buf = &read_http_connection($hc, 65536))) {
		$raw .= $buf;
		}
	&close_http_connection($hc);
	alarm(0);
	if (($hdr{"transfer-encoding"} || "") =~ /chunked/i) {
		my $dec = "";
		while($raw =~ s/^([0-9a-fA-F]+)[^\r\n]*\r?\n//) {
			my $n = hex($1);
			last if (!$n);
			$dec .= substr($raw, 0, $n);
			$raw = substr($raw, $n);
			$raw =~ s/^\r?\n//;
			}
		$raw = $dec;
		}
	if (($hdr{"content-type"} || "") =~ /json/ && $raw =~ /^\s*[\{\[]/) {
		$data = eval { &pihole_from_json($raw) };
		$data = $raw if ($@);
		}
	else {
		$data = $raw;
		}
	};
alarm(0);
$err ||= $@ eq "timeout\n" ? $text{'pihole_etimeout'} : $@ if ($@);
$err ||= $text{'pihole_ebadreply'} if (!$err && !$status);
return ( $status, $data, $err );
}

# pihole_sid_file()
sub pihole_sid_file
{
# Webmin 1.990 and later have a private data directory for each module, which
# unlike the config directory is not part of configuration backups
return $module_var_directory && -d $module_var_directory ?
	"$module_var_directory/pihole.sid" : "$module_config_directory/pihole.sid";
}

# pihole_login([force])
# Gets a session from the API using the CLI password, reusing a saved one
# when possible. Returns undef on success or an error message.
sub pihole_login
{
my ($force) = @_;
return undef if ($pihole_open);
if (!$force && !$pihole_sid) {
	my $saved = &read_file_contents(&pihole_sid_file());
	$saved =~ s/\s+//g;
	$pihole_sid = $saved if ($saved =~ /^[A-Za-z0-9+\/=]+$/);
	}
return undef if ($pihole_sid && !$force);
$pihole_sid = undef;
my $pw = &read_file_contents($pihole_clipw);
$pw =~ s/\s+$//;
my ($st, $d, $err) = &pihole_http("POST", "/auth",
				  { 'password' => $pw ne '' ? $pw : "" });
return $err if ($err);
if (ref($d) && $d->{'session'} && $d->{'session'}->{'valid'}) {
	if (!$d->{'session'}->{'sid'}) {
		# No password is set in Pi-hole, so the API is open
		$pihole_open = 1;
		return undef;
		}
	$pihole_sid = $d->{'session'}->{'sid'};
	# The session is a credential, so the file is never readable by others
	my $f = &pihole_sid_file();
	my $oldmask = umask(077);
	&open_tempfile(SID, ">$f", 0, 1);
	&print_tempfile(SID, $pihole_sid."\n");
	&close_tempfile(SID);
	umask($oldmask);
	&set_ownership_permissions(undef, undef, 0600, $f);
	# Versions up to 1.6 kept it in the config directory
	my $old = "$module_config_directory/pihole.sid";
	&unlink_file($old) if ($old ne $f && -e $old);
	return undef;
	}
return -r $pihole_clipw ? $text{'pihole_eauth'} : $text{'pihole_eclipw'};
}

# pihole_api(method, path, [&body])
# Calls the API with a valid session. Returns ( data, error ).
sub pihole_api
{
my ($method, $path, $body) = @_;
my $err = &pihole_login();
return ( undef, $err ) if ($err);
my ($st, $d, $herr) = &pihole_http($method, $path, $body);
for(my $i=0; $i<3 && $herr && !$st; $i++) {
	# Connection refused while pihole-FTL restarts, so try again shortly
	sleep(1);
	($st, $d, $herr) = &pihole_http($method, $path, $body);
	}
if (!$herr && $st == 401 && !$pihole_open) {
	# Saved session expired, so log in again once
	$err = &pihole_login(1);
	return ( undef, $err ) if ($err);
	($st, $d, $herr) = &pihole_http($method, $path, $body);
	}
return ( undef, $herr ) if ($herr);
if ($st >= 400) {
	my $msg = ref($d) && $d->{'error'} ?
		($d->{'error'}->{'message'} || $d->{'error'}->{'key'}).
		($d->{'error'}->{'hint'} ? " : ".$d->{'error'}->{'hint'} : "") :
		"HTTP $st";
	return ( $d, $msg );
	}
return ( $d, undef );
}

# pihole_get(path)
# Shortcut for GET requests that returns just the data, or undef
sub pihole_get
{
my ($d, $err) = &pihole_api("GET", $_[0]);
$pihole_last_error = $err;
return $err ? undef : $d;
}

# pihole_path_part(string)
# Encodes one part of an API path, like a domain or list URL
sub pihole_path_part
{
my ($s) = @_;
$s =~ s/([^A-Za-z0-9\-\._~])/sprintf("%%%02X", ord($1))/ge;
return $s;
}

# pihole_config(path)
# Returns one setting from the Pi-hole config, like dns/upstreams
sub pihole_config
{
my ($path) = @_;
my $d = &pihole_get("/config/".$path);
return undef if (!$d);
my $v = $d->{'config'};
foreach my $p (split(/\//, $path)) {
	return undef if (ref($v) ne 'HASH');
	$v = $v->{$p};
	}
return $v;
}

# pihole_set_config(path, value)
# Changes one setting, like dns/upstreams. Returns an error or undef.
sub pihole_set_config
{
my ($path, $value) = @_;
# API sessions opened with the CLI password may not change settings, so use
# Pi-hole's own command, which the running server picks up at once
&has_command("pihole-FTL") || return $text{'pihole_eftlcmd'};
my $key = join(".", split(/\//, $path));
$key =~ /^[A-Za-z0-9\.]+$/ || return $text{'pihole_eaction'};
my $v = ref($value) ? &pihole_to_json($value) : $value;
my $out = &backquote_logged("pihole-FTL --config ".quotemeta($key)." ".
			    quotemeta($v)." 2>&1 </dev/null");
return "<pre>".&html_escape($out)."</pre>" if ($?);
# Changing DNS settings makes pihole-FTL restart, so wait until it answers
# again before anything else talks to it
sleep(1);
for(my $i=0; $i<15; $i++) {
	my ($st) = &pihole_http("GET", "/auth");
	# The web server can be up before the API is, and answer 404
	last if ($st == 200 || $st == 401);
	sleep(1);
	}
return undef;
}

# unbound_upstream()
# Returns the address#port that Pi-hole should use to reach this Unbound
sub unbound_upstream
{
# Address set by hand in the module configuration, like 127.0.0.1#5335,
# 127.0.0.1:5335, [::1]:5335, :5335 or just 5335
my $set = $config{'unbound_addr'};
$set =~ s/\s+//g;
if ($set ne '') {
	my ($a, $p);
	if ($set =~ /^\d+$/) { ($a, $p) = ("127.0.0.1", $set); }
	elsif ($set =~ /^:(\d+)$/) { ($a, $p) = ("127.0.0.1", $1); }
	elsif ($set =~ /^\[([^\]]+)\](?:[:#](\d+))?$/) { ($a, $p) = ($1, $2); }
	elsif ($set =~ /^(.*)#(\d+)$/) { ($a, $p) = ($1, $2); }
	elsif ($set =~ /^([^:]+):(\d+)$/) { ($a, $p) = ($1, $2); }
	else { $a = $set; }
	$p ||= 53;
	return $a.($p == 53 ? "" : "#".$p)
		if (&check_ipaddress($a) || &check_ip6address($a));
	}
my @mine = &config_listen_addrs();
my ($l) = grep { $_->[0] =~ /^(127\.0\.0\.1|0\.0\.0\.0)$/ } @mine;
$l ||= (grep { $_->[0] eq '::1' || $_->[0] eq '::' } @mine)[0];
$l ||= $mine[0];
return undef if (!$l);
my $a = $l->[0] eq '0.0.0.0' ? '127.0.0.1' : $l->[0] eq '::' ? '::1' : $l->[0];
return $a.($l->[1] == 53 ? "" : "#".$l->[1]);
}

# pihole_local_suffixes()
# Returns domains that Pi-hole answers itself and never forwards, unless a
# conditional forwarding rule says otherwise
sub pihole_local_suffixes
{
my @rv = ( "home.arpa.", "internal." );
my $dom = &pihole_toml_value("dns.domain", "name") || "lan";
my $loc = &pihole_toml_value("dns.domain", "local");
push(@rv, &canonical_name($dom)) if ($loc ne 'false');
return &unique(@rv);
}

# hidden_local_zones(&revservers)
# Returns Unbound local zones that Pi-hole would answer itself instead of
# sending to Unbound
sub hidden_local_zones
{
my ($rev) = @_;
my @suf = &pihole_local_suffixes();
my $up = &unbound_upstream();
my %fwd;
foreach my $r (@{$rev || [ ]}) {
	my ($on, $cidr, $srv, $dom) = split(/,/, $r);
	# Only rules that really send the queries to Unbound count, not ones
	# left pointing at an old port or at another server
	$srv =~ s/#53$//;
	$fwd{&canonical_name($dom)} = 1
		if ($on eq 'true' && $dom && $srv eq $up);
	}
my @rv;
foreach my $z (&list_local_zones()) {
	my $n = &canonical_name($z->{'name'});
	next if (!grep { $n eq $_ || $n =~ /\.\Q$_\E$/ } @suf);
	# Covered by a forwarding rule for it or a parent?
	my $covered = 0;
	foreach my $f (keys %fwd) {
		$covered = 1 if ($n eq $f || $n =~ /\.\Q$f\E$/);
		}
	push(@rv, $n) if (!$covered);
	}
return @rv;
}

# local_zone_ranges(zone)
# Returns the private ranges (like 192.168.0.0/16) that the A records of a
# local zone point into
sub local_zone_ranges
{
my ($zone) = @_;
my %r;
foreach my $rec (&list_local_records()) {
	next if ($rec->{'type'} ne 'A');
	my $n = &canonical_name($rec->{'name'});
	next if ($n ne $zone && $n !~ /\.\Q$zone\E$/);
	foreach my $net ("192.168.0.0/16", "10.0.0.0/8", "172.16.0.0/12") {
		$r{$net}++ if (&net_contains($net, $rec->{'data'}));
		}
	}
return sort { $r{$b} <=> $r{$a} } keys %r;
}

# pihole_fix_revservers(&current)
# Returns a new conditional forwarding list that sends the hidden local
# zones to Unbound, keeping the entries the user already had
sub pihole_fix_revservers
{
my ($cur) = @_;
my $up = &unbound_upstream();
my @hidden = &hidden_local_zones($cur);
my %hidden = map { $_, 1 } @hidden;
# Drop old rules for exactly these zones, like ones for a previous port
my @rv = grep { my @f = split(/,/, $_);
		!$hidden{&canonical_name($f[3] || ".")} } @{$cur || [ ]};
foreach my $z (@hidden) {
	my ($range) = &local_zone_ranges($z);
	$range ||= "192.168.0.0/16";
	my $d = $z;
	$d =~ s/\.$//;
	push(@rv, join(",", "true", $range, $up, $d));
	}
return \@rv;
}

# pihole_ftl_running()
sub pihole_ftl_running
{
foreach my $p (&find_byname("pihole-FTL")) {
	my $stat = &read_file_contents("/proc/$p/stat");
	return $p if ($stat =~ /^\d+\s+\(pihole-FTL\)\s+[^ZX]/);
	}
return 0;
}

# pihole_time(unix-time)
sub pihole_time
{
my ($t) = @_;
return "-" if (!$t);
return &make_date(int($t));
}

1;
