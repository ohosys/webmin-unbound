#!/usr/local/bin/perl
# Add, enable, disable or delete Pi-hole blocklists and allowlists

require './unbound-lib.pl';
require './pihole-lib.pl';
&ReadParse();
&error_setup($text{'pihole_lerr'});
&can_edit('pihole') || &error($text{'pihole_ecannot'});

if ($in{'add'}) {
	$in{'type'} =~ /^(block|allow)$/ || &error($text{'pihole_elist'});
	my @addrs = grep { /\S/ } map { s/^\s+|\s+$//g; $_ }
			 split(/\r?\n/, $in{'address'});
	@addrs || &error($text{'pihole_enoaddress'});
	foreach my $a (@addrs) {
		$a =~ /^(https?|file):\/\/\S+$/ ||
			&error(&text('pihole_eaddress', &html_escape($a)));
		}
	my ($d, $err) = &pihole_api("POST", "/lists?type=$in{'type'}",
		{ 'address' => \@addrs, 'comment' => $in{'comment'},
		  'groups' => [ 0 ], 'enabled' => \1 });
	&error($err) if ($err);
	&webmin_log("pihole_add", "list", join(" ", @addrs));
	}
else {
	my @d = split(/\0/, $in{'d'});
	@d || &error($text{'pihole_enone'});
	my $all = &pihole_get("/lists") || { };
	foreach my $v (@d) {
		my ($type, $addr) = split(/\//, $v, 2);
		$type =~ /^(block|allow)$/ || &error($text{'pihole_elist'});
		my $path = "/lists/".&pihole_path_part($addr)."?type=$type";
		my ($r, $err);
		if ($in{'delete'}) {
			($r, $err) = &pihole_api("DELETE", $path);
			}
		else {
			my ($l) = grep { $_->{'address'} eq $addr &&
					 $_->{'type'} eq $type }
				       @{$all->{'lists'} || [ ]};
			$l || &error($text{'pihole_elistgone'});
			($r, $err) = &pihole_api("PUT", $path,
				{ 'comment' => $l->{'comment'},
				  'groups' => $l->{'groups'},
				  'type' => $type,
				  'enabled' => $in{'enable'} ? \1
							     : \0 });
			}
		&error($err) if ($err);
		}
	&webmin_log($in{'delete'} ? "pihole_delete" :
		    $in{'enable'} ? "pihole_enablelist" : "pihole_disablelist",
		    "lists", scalar(@d));
	}
&redirect("pihole.cgi?mode=lists");
