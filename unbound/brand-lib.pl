# brand-lib.pl
# Light visual layer shared by the Unbound and Pi-hole pages: a header with
# the project logo, a switch between the two parts of the module, coloured
# statistic tiles and bars. Plain CSS, no external files; works with the
# Authentic theme (light and dark) and the old Webmin theme.

our $brand_css_done;

# brand_css()
# Returns the style block, only the first time it is called
sub brand_css
{
return "" if ($brand_css_done++);
return <<'EOF';
<style>
.ubx-head{display:flex;align-items:center;gap:14px;flex-wrap:wrap;padding:10px 14px;margin:4px 0 12px;border-radius:6px;background:linear-gradient(90deg,rgba(49,100,180,.12),rgba(49,100,180,.03) 55%,rgba(194,16,27,.07));border:1px solid rgba(49,100,180,.22)}
.ubx-head>img{width:52px;height:52px;flex:none}
.ubx-name{font-size:17px;font-weight:600;line-height:1.25}
.ubx-sub{opacity:.72;font-size:12.5px}
.ubx-pills{margin-left:auto;display:flex;gap:8px;flex-wrap:wrap}
.ubx-pill{display:inline-flex;align-items:center;gap:6px;padding:3px 11px;border-radius:13px;font-size:12px;background:rgba(127,127,127,.13);white-space:nowrap}
.ubx-pill i{font-size:12px!important}
.ubx-dot{width:8px;height:8px;border-radius:50%;display:inline-block}
.ubx-ok{background:#1aa34a}.ubx-off{background:#d9534f}.ubx-mid{background:#f0ad4e}
.ubx-switch{display:flex;flex-wrap:wrap;margin:0 0 14px;border-bottom:2px solid rgba(127,127,127,.18)}
.ubx-switch a{display:inline-flex;align-items:center;gap:7px;padding:7px 18px 8px;font-weight:600;font-size:14px;text-decoration:none!important;border-bottom:3px solid transparent;margin-bottom:-2px;color:inherit!important;opacity:.62}
.ubx-switch a:hover{opacity:.9}
.ubx-switch a.on{opacity:1}
.ubx-switch a.u.on{border-color:#3164b4}
.ubx-switch a.p.on{border-color:#c2101b}
.ubx-switch i{font-size:16px!important;width:18px;text-align:center}
.ubx-switch a.u i{color:#3164b4}
.ubx-switch a.p i{color:#c2101b}
.ubx-tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(175px,1fr));gap:10px;margin:0 0 14px}
.ubx-tile{position:relative;border-radius:5px;color:#fff!important;padding:11px 14px 10px;overflow:hidden;min-height:74px;box-shadow:0 1px 2px rgba(0,0,0,.12)}
.ubx-tile b{display:block;font-size:24px;font-weight:700;line-height:1.15;color:#fff}
.ubx-tile span{font-size:12.5px;opacity:.95;color:#fff}
.ubx-tile i{position:absolute;right:12px;top:12px;font-size:42px!important;opacity:.22;color:#fff}
.ubx-c1{background:#00a65a}.ubx-c2{background:#00c0ef}.ubx-c3{background:#f39c12}.ubx-c4{background:#dd4b39}
.ubx-u1{background:#3164b4}.ubx-u2{background:#1d9a6c}.ubx-u3{background:#1f3560}.ubx-u4{background:#6b7fa8}
.ubx-bar{height:7px;border-radius:4px;background:rgba(127,127,127,.18);overflow:hidden;min-width:70px}
.ubx-bar>div{height:100%;border-radius:4px}
.ubx-badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11.5px;color:#fff;background:#6b7fa8}
.ubx-flow{display:flex;align-items:stretch;flex-wrap:wrap;gap:0;margin:4px 0 16px}
.ubx-node{flex:1 1 150px;display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:6px;border:1px solid rgba(127,127,127,.25);border-top:4px solid #6b7fa8;background:rgba(127,127,127,.05)}
.ubx-node.ok{border-top-color:#1aa34a}.ubx-node.off{border-top-color:#d9534f}.ubx-node.mid{border-top-color:#f0ad4e}
.ubx-node img{width:28px;height:30px;object-fit:contain;flex:none}
.ubx-node i{font-size:24px!important;width:28px;text-align:center;opacity:.7;flex:none}
.ubx-node b{display:block;font-size:13.5px}
.ubx-node small{opacity:.75;font-size:12px}
.ubx-arrow{display:flex;align-items:center;padding:0 6px;font-size:20px;opacity:.45}
</style>
EOF
}

# brand_header(part, &pills)
# Returns the logo header and the Unbound / Pi-hole switch. part is unbound or
# pihole. Each pill is [ state (ok, off, mid or undef), html ]
sub brand_header
{
my ($part, $pills) = @_;
my $rv = &brand_css();
$rv .= "<div class='ubx-head'>";
$rv .= "<img src='images/logo.svg' alt=''>";
# Without Pi-hole the module only manages Unbound, so say only that
my $pi = &pihole_installed_quick();
$rv .= "<div><div class='ubx-name'>".
       $text{$pi ? 'brand_name' : 'brand_nameu'}."</div>".
       "<div class='ubx-sub'>".
       $text{$pi ? 'brand_tagline' : 'brand_taglineu'}."</div></div>";
if ($pills && @$pills) {
	$rv .= "<div class='ubx-pills'>";
	foreach my $p (@$pills) {
		$rv .= "<span class='ubx-pill'>".
		       ($p->[0] ? "<span class='ubx-dot ubx-$p->[0]'></span>"
				: "").$p->[1]."</span>";
		}
	$rv .= "</div>";
	}
$rv .= "</div>\n";
my $showpi = &can_edit('pihole') && &pihole_installed_quick();
if ($showpi) {
	$rv .= "<div class='ubx-switch'>";
	$rv .= "<a class='u".($part eq 'unbound' ? " on" : "").
	       "' href='index.cgi'><i class='fa fa-server'></i>".
	       "Unbound</a>";
	$rv .= "<a class='p".($part eq 'pihole' ? " on" : "").
	       "' href='pihole.cgi'><i class='fa fa-shield'></i>".
	       "Pi-hole</a>";
	$rv .= "</div>\n";
	}
return $rv;
}

# brand_badge(text, colour)
# Returns a small coloured label, like Pi-hole uses for query states
sub brand_badge
{
my ($t, $col) = @_;
return &brand_css()."<span class='ubx-badge' style='background:$col'>".
       &html_escape($t)."</span>";
}

# brand_flow(&nodes)
# Returns a left-to-right diagram of a query's path. Each node is
# [ icon, title, detail-html, state ], where icon is unbound, pihole or a
# Font Awesome name, and state is ok, off or mid
sub brand_flow
{
my ($nodes) = @_;
my $rv = &brand_css()."<div class='ubx-flow'>";
my $first = 1;
foreach my $n (@$nodes) {
	$rv .= "<div class='ubx-arrow'>&#10140;</div>" if (!$first);
	$first = 0;
	my $fa = $n->[0] eq 'unbound' ? 'server' :
		 $n->[0] eq 'pihole' ? 'shield' : $n->[0];
	my $icon = "<i class='fa fa-$fa'></i>";
	$rv .= "<div class='ubx-node $n->[3]'>$icon<div><b>$n->[1]</b>".
	       "<small>$n->[2]</small></div></div>";
	}
return $rv."</div>\n";
}

# pihole_installed_quick()
# Same as pihole_installed, without loading the Pi-hole library
sub pihole_installed_quick
{
return -r "/etc/pihole/pihole.toml" ? 1 : 0;
}

# brand_tiles(&tiles)
# Returns a row of coloured tiles. Each is [ class, value, label, fa-icon ]
sub brand_tiles
{
my ($tiles) = @_;
my $rv = &brand_css()."<div class='ubx-tiles'>";
foreach my $t (@$tiles) {
	$rv .= "<div class='ubx-tile ubx-$t->[0]'>".
	       ($t->[3] ? "<i class='fa fa-$t->[3]'></i>" : "").
	       "<b>$t->[1]</b><span>$t->[2]</span></div>";
	}
return $rv."</div>\n";
}

# brand_bar(value, max, colour)
# Returns a small horizontal bar showing value as a share of max
sub brand_bar
{
my ($v, $max, $col) = @_;
$v = int($v || 0);
my $pc = $max > 0 ? int(100*$v/$max + 0.5) : 0;
$pc = 100 if ($pc > 100);
return &brand_css()."<div class='ubx-bar' title='$v'>".
       "<div style='width:$pc%;background:$col'></div></div>";
}

# brand_pct(n)
# Formats a percentage with one decimal, using the language's separator
sub brand_pct
{
my ($n) = @_;
my $v = sprintf("%.1f", $n);
$v =~ s/\./$text{'brand_decsep'}/ if ($text{'brand_decsep'});
return $v."%";
}

# brand_number(n)
# Formats a number with thousands separators
sub brand_number
{
my ($n) = @_;
$n = int($n);
my $sep = $text{'brand_thsep'} || ",";
1 while ($n =~ s/^(-?\d+)(\d{3})/$1$sep$2/);
return $n;
}

1;
