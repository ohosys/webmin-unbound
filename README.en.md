<p align="center"><img src="branding/banner.png" alt="webmin-unbound: Webmin + Unbound + Pi-hole" width="100%"></p>

# <img src="branding/logo.svg" alt="" width="48" align="top"> Webmin module for Unbound DNS and Pi-hole

**English** · [Italiano](README.md)

**⬇️ Download: [unbound.wbm.gz](https://github.com/ohosys/webmin-unbound/releases/latest/download/unbound.wbm.gz)** (latest version, to install in Webmin; all versions on the [releases](https://github.com/ohosys/webmin-unbound/releases/latest) page).

> Do not use *Code → Download ZIP* or the release *Source code* archives: they hold the
> whole repository, not the module, and Webmin answers "missing a module.info file".

A Webmin module (Perl, in the same style as the official modules) to manage
**Unbound** and, on the same machine, **Pi-hole 6** using it as its upstream server
(the setup from the [official guide](https://docs.pi-hole.net/guides/dns/unbound/)).

**In short:** one Webmin page manages the whole DNS chain of a home or office:
Pi-hole answers the clients and blocks ads and trackers; Unbound resolves
recursively, validates DNSSEC and holds the local names of the network. The module
keeps the two in step (cache, forwarding of local zones, upstreams) and warns before
any change that would leave the network without DNS.

For Unbound:
local zones and records, bulk import, forward, stub and authoritative zones, RPZ
blocklists, client views, access control, DNSSEC, cache and statistics. User
interface in English and Italian. Version 1.7.

Tested on **Ubuntu 24.04** (deb), **Rocky Linux 9** and **Fedora 42** (rpm).
Pi-hole is optional: without it, the module manages Unbound only.

It is integrated with the rest of Webmin like an official module:
- **System and Server Status**: monitors with email alerts.
- **Dashboard**: status and statistics.
- **System Logs**: the Unbound log file.
- **Global search**: direct links to the module pages.
- **Bug reports**: attaches the configuration files.
- **Configuration backup**.
- **Network Configuration**: sets the system resolver.

## Installation

1. Webmin → *Webmin Configuration* → *Webmin Modules* → *Install Module*, then:
   - *From uploaded file*: the [unbound.wbm.gz](https://github.com/ohosys/webmin-unbound/releases/latest/download/unbound.wbm.gz) file downloaded from the link
     above (the same as `dist/unbound-1.7.wbm.gz` in this repository; to rebuild it from
     source: `./make-package.sh`);
   - or *From ftp or http URL*: `https://github.com/ohosys/webmin-unbound/releases/latest/download/unbound.wbm.gz`
     (Webmin must be able to make HTTPS connections, i.e. have the `Net::SSLeay` Perl module).
2. The module appears under *Servers → Unbound DNS Server*.
3. New settings go into a separate file, created on the first save:
   `/etc/unbound/unbound.conf.d/webmin.conf` on Debian/Ubuntu,
   `/etc/unbound/conf.d/webmin.conf` on Rocky/Alma/RHEL/Fedora.

Requirements: Unbound with `unbound-checkconf` and `unbound-control`, with
`control-enable: yes` (the default on Debian/Ubuntu).
Recommended: `dig` (test queries and monitors) and `ss` (port 53 diagnostics).

## Pi-hole management (*Pi-hole* icon on the module page)

Shown when Pi-hole 6 is installed on the machine. The module uses the Pi-hole REST API
with the local command-line password (`/etc/pihole/cli_pw`, the same one used by the
`pihole` command): **there is no need to enter or store the Pi-hole password**.
Pi-hole settings are changed with the official `pihole-FTL --config` command, because
Pi-hole does not allow changing them with that kind of access.

| Tab | Functions |
|---|---|
| Status | Blocking on/off (also for 30 s, 5 min, 1 h), statistics for the last 24 hours, top blocked and top requested domains, most active clients, upstream servers; *Update Gravity*, *Restart Pi-hole DNS* |
| Link to Unbound | Checks that Pi-hole uses only Unbound and sets it with one click; finds the Unbound local zones that Pi-hole does not forward (see below) and links them |
| Allow and block | Exact domains and regular expressions, multiple add, delete; search for a domain in rules and lists |
| Lists | Blocklists and allowlists: add (http, https, file), enable, disable, delete, Gravity update with visible output |
| Query log | Latest queries with filters by domain, client, blocked only or allowed only; *Allow* / *Block* on each row |
| Clients | Pi-hole clients and groups: add by IP, network, MAC or interface, delete |
| Network | Devices seen by Pi-hole (IP, name, MAC, vendor, last query) and Pi-hole DHCP leases, which can be imported as records into an Unbound local zone |

Also: a Pi-hole box on the Webmin **dashboard**, a **"Pi-hole running"** monitor in
*System and Server Status* (with email alerts), a dedicated user permission, and every
action in the Webmin log.

**Problem found and fixed: `.lan` zones did not reach the clients.** Pi-hole 6 treats
`.lan` (its default domain), `home.arpa` and `.internal` as local and never forwards
those queries: a `home.lan` zone created in Unbound answers `dig` on port 5335, but the
clients get NXDOMAIN from Pi-hole. The *Forward local zones* button adds a conditional
forwarding rule in Pi-hole for each zone (for example
`true,192.168.0.0/16,127.0.0.1#5335,home.lan`): only those zones and their reverse
lookups go to Unbound, other `.lan` names stay with Pi-hole.

Note: changing the upstreams or conditional forwarding **restarts pihole-FTL**
(about one second without DNS); the module says so first and waits until it is back.

## Use with Pi-hole

Supported setup: the one from the
[official guide](https://docs.pi-hole.net/guides/dns/unbound/), with Pi-hole on
port 53 and Unbound on `127.0.0.1#5335` as the only upstream server. The module
detects Pi-hole 6 or dnsmasq from port 53. It reads their configuration files
(`/etc/pihole/pihole.toml`, `/etc/dnsmasq.d`) **without ever changing them** (changes
to Pi-hole go through its API or `pihole-FTL --config`).
**Pi-hole 6** is required: Pi-hole 5 is not supported.

| Risk | What the module does |
|---|---|
| Pi-hole caches old answers (up to one hour with the default TTL of 3600 s), so changes do not reach the clients | After each change it flushes the Pi-hole cache with SIGHUP, as `pihole reloaddns` does. DNS stays up. It can be turned off in the module configuration |
| Stopping Unbound leaves the whole network without DNS | *Stop* asks for confirmation, saying that Pi-hole depends on Unbound |
| Changing port or interfaces, or refusing `127.0.0.1` in access control, cuts off Pi-hole | *Apply* shows the problem and asks for confirmation |
| Moving Unbound to port 53 (used by Pi-hole) would stop it | *Apply* and *Start* refuse, and Unbound stays up |
| The "use Unbound as system resolver" button would point `/etc/resolv.conf` at Pi-hole, not Unbound | With Unbound on a port other than 53 the button is gone. Diagnostics say to use Pi-hole |

Other points of the guide that the module checks (*Check configuration* page):

| Point of the guide | What the module does |
|---|---|
| `private-address` (11 networks) | A forward or stub zone to the router or an internal DNS would answer with no addresses: tested, `NOERROR` with an empty answer. Zones have two options, *Accept private addresses* (`private-domain`) and *Skip DNSSEC* (`domain-insecure`), on by default for new zones. Diagnostics report zones without these options |
| AppArmor and `logfile: /var/log/unbound/unbound.log` | If the AppArmor profile does not allow writing the log or the downloaded zone files, it shows the exact line to add to `/etc/apparmor.d/local/usr.sbin.unbound` |
| `unbound-resolvconf.service` (Debian Bullseye and later) | If `resolvconf_resolvers.conf` exists with a forward for `.`, it warns that Unbound is not resolving by itself and shows the commands from the guide |
| `so-rcvbuf: 1m` | If it exceeds `net.core.rmem_max`, it shows the `sysctl` commands |

Note:
- "Local DNS" records defined in Pi-hole take precedence over Unbound ones.
- Pi-hole blocklists act before Unbound: a name blocked by Pi-hole never
  reaches Unbound RPZs or local records.
- If Pi-hole has upstream servers other than Unbound, diagnostics report it:
  Unbound local records do not apply to those answers.

## deb and rpm distributions

The same package works on **Debian/Ubuntu** and on **Rocky/Alma/RHEL/Fedora**.
Tested on Ubuntu 24.04, Rocky Linux 9.8 (with Pi-hole 6) and Fedora 42 (Unbound only),
always with Webmin 2.670 and Unbound from the distribution packages.

**Pi-hole is optional.** Without Pi-hole the module manages Unbound only: the header
shows "Unbound DNS", and the switcher and Pi-hole pages do not appear.

**The user chooses the Unbound port.** The module reads it from the Unbound
configuration (`port:` or `interface: address@port`), whatever it is (53, 5335, 5454…).
If it must be set by hand for the link with Pi-hole, the module configuration has the
*Unbound address used by Pi-hole* option, which accepts `127.0.0.1#5335`,
`127.0.0.1:5335`, `[::1]:5335`, `:5335` or just `5335`.

| Difference between distributions | What the module does |
|---|---|
| Debian reads `/etc/unbound/unbound.conf.d/*.conf`, RHEL/Fedora `/etc/unbound/conf.d/*.conf` | Writes `webmin.conf` in the directory that the configuration really includes, whatever the setting. If a file is in a directory that is not read (for example the Pi-hole guide file copied into `unbound.conf.d` on Rocky), *Check configuration* reports it and the *Make Unbound read it* button adds the `include:` (checked, and rolled back if the configuration is not valid) |
| Fedora has an empty `remote-control:` section in `unbound.conf` and the real one in an included file | Considers all sections, as Unbound does |
| SELinux (RHEL/Fedora) | Pi-hole does not support SELinux: anyone using Pi-hole with this module must disable it, as Pi-hole requires. If SELinux is enforcing and Pi-hole is installed, *Check configuration* reminds you. Without Pi-hole the module manages Unbound alone and, with SELinux enforcing, only reports when the chosen Unbound port is not allowed |
| AppArmor (Debian/Ubuntu) | Checks that Unbound can write logs and zone files |
| JSON | Webmin ships `JSON::PP` (in `vendor_perl`) and needs it itself, so nothing has to be installed. If it were missing, the Pi-hole pages use a built-in parser and *Check configuration* offers the link to install it |

## Security

- **Permissions**: 12 permissions per Webmin user (one per area, plus *Pi-hole*). Every
  page checks them, including those that perform an action; the module configuration
  follows the standard Webmin permission *Can edit module configuration*.
- **Cross-site requests**: the module uses the standard Webmin protection (Referer
  check); no page turns it off.
- **Commands**: every argument passed to `unbound-control`, `unbound-checkconf`, `dig`
  and `pihole-FTL` is validated and escaped with `quotemeta`.
- **Configuration files**: values with newlines or control characters are refused,
  names and addresses are validated, and after each change `unbound-checkconf` checks
  the result and restores the files on error. Manual editing is limited to the files
  that Unbound reads.
- **Data from the network**: query log domains, client names, DHCP leases and Pi-hole
  API responses are always shown HTML-escaped.
- **Pi-hole credentials**: the module neither asks for nor stores the Pi-hole password;
  it uses `/etc/pihole/cli_pw`, readable by root only. The API address must be on this
  system (loopback or one of its own IP addresses), so `cli_pw` is never sent to other
  machines. The API session is stored in `/var/webmin/modules/unbound/pihole.sid` with
  mode 0600.

Security problems: use *Security → Report a vulnerability* on this repository
(GitHub private reporting), not a public issue, and do not publish details before a
fix is released.

## Features

| Area | What it does | How |
|---|---|---|
| Local zones | Creates zones and A, AAAA, CNAME, MX, TXT, PTR, SRV, NS, CAA records; creates the PTR automatically | `local-zone`, `local-data`, `local-data-ptr` |
| **Immediate changes** | Local records and zones take effect at once, without reloading and without flushing the cache | `unbound-control local_data` / `local_zone` |
| **Bulk import** | From text (hosts or record format), from `/etc/hosts` or from DHCP leases (ISC dhcpd, Kea); preview; skips or replaces duplicates | equivalent of BIND's "Create zones from batch file" |
| Forward zones | Also DNS-over-TLS; `.` = everything | `forward-zone` |
| Stub zones | | `stub-zone` |
| Authoritative zones | From file, primary server or URL | `auth-zone` |
| **RPZ blocklists** | From file, URL or primary server; forced action (nxdomain, nodata, cname…), logging | `rpz:` + automatic `respip` activation |
| **Client views** | Different zones and records for groups of clients | `view:` + `access-control-view` |
| Access control | All `access-control` actions | |
| Options | ~70 options on 5 pages, with the real default read from `unbound-checkconf -o` | |
| Cache and statistics | Status, statistics, cache flush, lookup, test query | `unbound-control`, `dig` |
| **Diagnostics** | Port 53 conflicts (e.g. systemd-resolved), system resolver, DNSSEC trust anchor, remote control, access rules | `ss`, `/etc/resolv.conf` |
| **System resolver** | One button makes Unbound the system DNS, after a test query; refuses systems managed by systemd-resolved | `net` module API |
| Safe changes | After each save it runs `unbound-checkconf` and, on error, restores the files as they were | |
| Permissions | 12 permissions per Webmin user | `acl_security.pl` |

### Webmin integrations (hook points)
| File | Used by | Effect |
|---|---|---|
| `status_monitor.pl` | *System and Server Status* | "Unbound running" monitor (also via unbound-control) and "DNS answer" monitor (with expected answer) |
| `system_info.pl` | Dashboard | Warning when Unbound is stopped or the configuration has errors; table with queries, cache hits, resolution time and uptime |
| `syslog_logs.pl` + `syslog=1` | *System Logs* | The Unbound `logfile` appears among the logs |
| `cgi_args.pl` | Webmin global search | Results link straight to the right page |
| `feedback_files.pl` | Feedback/bug report | Attaches the configuration files |
| `backup_config.pl` | *Backup Configuration Files* | Configuration + zone files; applies the configuration after a restore |
| `log_parser.pl` | *Webmin Actions Log* | Readable descriptions of every action |

## Analysis: what can be ported from the Webmin DNS modules

Code analysis of `bind8`, `net`, `dhcpd`, `status`, `syslog`/`logviewer`,
`webmin-search-lib` and `web-lib-funcs`, plus observation of the pages in a real
browser (BIND, DNS client, Status and DHCP pages, and those of this module).

**Implemented** (Unbound has an equivalent):
- monitors, dashboard, logs, search, feedback, backup (Webmin hook points);
- BIND batch import and "Add record to selected" → bulk import;
- BIND client views → Unbound views;
- BIND `response-policy` → RPZ;
- "Check BIND Config" → check plus diagnostics;
- rndc → `unbound-control`, plus immediate record changes.

**Impossible with Unbound** (Unbound does not support it):
- RFC 2136 dynamic updates, i.e. the "DNS Zones" / DDNS section of the DHCP module.
  Alternative offered: import of DHCP leases;
- DNSSEC zone signing, NOTIFY to secondaries, `$GENERATE`, SOA editing;
- master zones with a file editable from Webmin: `auth-zone`s are read, not changed.

**Possible, but would need more** (not included):
- BIND *Cluster slave servers*: pushing the configuration to other Webmin servers
  via RPC. Needs linked Webmin servers and multi-host testing;
- automatic, continuous sync of DHCP leases: needs a cron job or a DHCP server
  hook (today the import is manual);
- historical statistics with graphs: needs a collector (like the *System Status*
  module) and disk space;
- scheduled blocklist updates: Unbound already does this for RPZs downloaded from
  a URL; other list formats would need a converter.

### Unbound behaviour found during testing
- `unbound-control reload` does **not** apply changes to the options of an existing
  RPZ: a full restart is needed. The module reports it and the *Apply* button
  restarts.
- `respip` (needed for RPZ) is not accepted together with `subnetcache`, which
  Debian/Ubuntu enable by default. The module removes `subnetcache`, unless EDNS
  Client Subnet is configured (in that case it gives a clear error).
- The names `.test`, `.localhost`, `.invalid`, `.onion`, `home.arpa` are reserved
  zones in Unbound and take precedence over authoritative zones.

### Problems found in Webmin itself (not in this module)
- `check_ip6address("bad")` returns true: any string of hex digits alone is accepted
  as IPv6. The module uses a stricter check.
- The *Status* module uses seconds as monitor IDs: two monitors created in the same
  second overwrite each other.
- `install-module.pl` from the command line does not update `installed.cache`: until
  *Refresh Modules* is run, global search does not link to the module pages.
- In the official Dovecot module, values containing newlines end up in the
  configuration file as they are.

## Known limits
- `include:` with a relative path is resolved against the directory of
  `unbound.conf`, while Unbound resolves it against its own working directory.
  Use absolute paths.
- chroot (the default on FreeBSD/OpenBSD) is not translated.
  Tested on Ubuntu, Rocky Linux 9 and Fedora 42.
- Pi-hole 6 is required; Pi-hole 5 is not supported.
- SELinux enforcing has not been tested: with Pi-hole it must be disabled, as Pi-hole
  requires.
- Access with `cli_pw` has not been tested with two-factor authentication (TOTP)
  enabled in Pi-hole.
- The RPZ `cname` override has not been verified: it needs resolution of the target
  name over the Internet, which the test environment did not have.
- The `config-*` files for SUSE, FreeBSD, OpenBSD and macOS contain standard,
  unverified paths (the RedHat one was tested on Rocky 9).

## Tests

**Version 1.7, full review and security.** Webmin 2.670 and Pi-hole 6.
- Ubuntu 24.04: every page opened with Perl warnings on, no errors;
  Rocky Linux 9: package installed and every page opened over HTTP, no errors in the
  Webmin log;
- Ubuntu, every CGI tried with hostile HTML values in all parameters: no value shown
  unescaped;
- Ubuntu, Webmin user with only the *Local zones* permission: all other pages and
  actions refused, including start, stop, Pi-hole and manual editing;
- Pi-hole API address on an external host: refused, the module stays on the local one;
  an IP address of the machine is accepted;
- API session moved to `/var/webmin/modules/unbound` (0600), old file removed;
- import with an invalid IP: row refused, the others imported;
- domain added to and removed from Pi-hole on both distributions, checked with `dig`
  and in the Pi-hole database; automated tests (`tests/run.sh`).

**Version 1.6, deb and rpm.**
- Rocky 9 with Pi-hole 6: Unbound moved to port 5454; *Use only Unbound* moves Pi-hole
  to `127.0.0.1#5454`, *Forward local zones* replaces the rules left on the old port;
  module setting from Debian (`unbound.conf.d`) but records written automatically to
  `conf.d/webmin.conf`; *Make Unbound read it* on `unbound.conf.d` and the zone inside
  resolved through Pi-hole; manual address tried in all forms; Pi-hole pages with the
  built-in JSON parser (`JSON::PP` hidden).
- Fedora 42 without Pi-hole, Unbound on port 53: installation, every page, zone and
  record applied at once, "Unbound DNS" header with no Pi-hole parts.
- Ubuntu 24.04 with Pi-hole 6: no regressions (records in `unbound.conf.d`, also
  resolved through Pi-hole, AppArmor OK).

**Version 1.5, Rocky Linux 9 (RPM).** Container with systemd: Unbound 1.24.2 from
`dnf`, Webmin 2.670 from the official repository, Pi-hole 6 (FTL v6.8) with the
official installer (`--unattended`), setup from the guide in `conf.d`.
The module was installed from the package and driven over HTTP:
- every page opened without errors;
- `home.lan` zone and records created in `conf.d/webmin.conf`, immediate answer from
  Unbound; *Forward local zones* makes `nas.home.lan` and its PTR resolve through
  Pi-hole too;
- exact and regex domains (also with an accented comment), blocking turned off and
  on again, `file://` list and Gravity, clients: all checked with `dig` and in the
  Pi-hole database;
- Pi-hole cache flush after a change (same FTL PID);
- dashboard and monitors; SELinux checks (simulated mode, real policy) and files not
  read;
- built-in JSON codec compared with `JSON::PP` (`tests/json.pl`).

**Version 1.4, with real Pi-hole.** pihole-FTL **v6.8** (official release) and core
scripts v6.5 installed as the installer does, web password set, Unbound on
`127.0.0.1#5335`, local blocklist. Everything driven by the module over HTTP and
checked with `dig` through Pi-hole:
- API access with `cli_pw`, session reused, new session after an FTL restart;
- *Forward local zones*: `nas.home.lan` and its PTR go from NXDOMAIN to the Unbound
  answer, `other.lan` stays with Pi-hole; *Use only Unbound* fixes mixed upstreams;
- exact and regex domains added and removed, a blocked domain answers 0.0.0.0;
  writes made during an FTL restart (3 out of 3 succeeded);
- `file://` list added, disabled, enabled again, Gravity updated from the module (the
  new domain is blocked), list removed;
- blocking turned off for 30 s with a countdown and turned on again; client added,
  invalid value refused, removed; search; "blocked only" filter; devices; Pi-hole DHCP
  leases shown and imported (expired lease left out);
- Pi-hole cache flush after changing a record (new IP at once, FTL not restarted);
  confirmation on *Stop*; diagnostics;
- Pi-hole monitor: up, down, up again; dashboard box;
- pages checked with the Authentic theme.

**Version 1.3.** Configuration updated to the guide (11 `private-address`, `do-ip6: yes`, log in `/var/log/unbound`). Forward zone to a simulated "router" DNS: empty answer without `private-domain`, with the module option `192.168.1.1` also through Pi-hole. Diagnostics tested for internal zones, AppArmor (static analysis of the profile: AppArmor is not active in the container), `resolvconf_resolvers.conf` and `so-rcvbuf`.

**Version 1.2, Pi-hole scenario.** Setup from the official guide (Unbound on
`127.0.0.1:5335`). Instead of Pi-hole, Ubuntu's dnsmasq ran on port 53 with a simulated
`/etc/pihole/pihole.toml`: pihole-FTL is a fork of dnsmasq, but the real binary was not
run. Checked with `dig` both on Unbound and through the server on port 53:
- records and PTRs created by the module resolved through the server on port 53;
- changing a record: without a cache flush the server on port 53 returned the old IP
  for an hour; with the flush it returns the new one at once;
- Unbound moved to port 53: *Apply* asks for confirmation, then refuses, and Unbound
  stays up; *Start* refuses;
- access control `127.0.0.0/8 refuse`: *Apply* and diagnostics report it;
- *Stop* asks for confirmation; stops and restarts correctly 5 times out of 5;
- installation from the `.wbm.gz` package with *Webmin Modules → Install*;
- pages checked with the Authentic theme (Webmin's default) and with Gray;
- 17 parser tests (`tests/run.sh`).

**Version 1.1:**
Ubuntu 24.04, Unbound 1.19.2, Webmin 2.670 installed from source. The module was
driven over HTTP and in a headless browser, checked with `dig` on the real server:
- all 9 record types; immediate changes without reload (the PTR too); stale edits
  refused;
- import from text (both formats), `/etc/hosts` and ISC leases (the expired lease is
  ignored), with preview and replace;
- RPZ: NXDOMAIN and nodata checked; restart flag; `respip` turned on automatically;
- view: the same name answers differently to the client of the view;
- monitor up/down/wrong answer; dashboard with Unbound up and down; log in the new
  *System Logs*; global search links;
- diagnostics and change of system resolver (then restored);
- automatic rollback after errors; injection attempts blocked; permissions;
- 17 parser unit tests (nested includes, comments, `#` inside quotes, directives on
  the same line as the section header, deleting sections in the middle of the file).

## Layout
```
unbound/
  unbound-lib.pl         parser, in-place writing, rollback, server control,
                         immediate changes, import, diagnostics
  index.cgi              main page: icons, 7 tabs, start/stop/apply
  edit_opts / save_opts  option pages (defined in option_pages())
  edit_access / save_access
  edit_local / save_local / edit_record / save_record / delete_records
  edit_batch / save_batch   bulk import
  edit_fwd / save_fwd    forward and stub zones
  edit_auth / save_auth  authoritative zones
  edit_rpz / save_rpz    RPZ blocklists
  edit_view / save_view  client views
  delete_zones.cgi       multiple delete (all types)
  control.cgi / control_run.cgi   unbound-control
  check.cgi / resolver.cgi        check, diagnostics, system resolver
  edit_manual / save_manual, start / stop / apply / bootup
  pihole-lib.pl          Pi-hole 6 API (cli_pw), detection of hidden zones
  brand-lib.pl           header with logo, Unbound / Pi-hole switcher, boxes
  fix_include.cgi        adds the include: for a directory that Unbound does not read
  pihole.cgi             Pi-hole page: status, link to Unbound, domains,
                         lists, query log, clients, network
  pihole_*.cgi           Pi-hole actions (blocking, gravity, domains, lists, clients)
  status_monitor.pl, system_info.pl, syslog_logs.pl, cgi_args.pl,
  feedback_files.pl, backup_config.pl, log_parser.pl, acl_security.pl,
  install_check.pl
  lang/en, lang/it, config-<os>, config.info(.it), module.info, defaultacl
  images/                page icons (from the bind8 module), SVG logo and marks
branding/                project logo (SVG, PNG 512) and banner
dist/                    installable package and SHA256SUMS
tests/                   parser and JSON codec tests (tests/run.sh)
```

License: BSD 3-Clause, like Webmin (see [LICENSE](LICENSE) and [NOTICE](NOTICE)).
The option icons come from the Webmin `bind8` module. The logo and banner combine the
logos of Webmin, Unbound (NLnet Labs) and Pi-hole, which remain the property of their
owners; this project is not affiliated with any of them.
