#!/usr/bin/perl
use strict; $|=1;

use utf8;
use feature qw( unicode_strings );

use CGI::Carp qw(fatalsToBrowser);

use HTML::Entities;
use Encode;
use CGI;
use JSON;
use LWP::Simple;
use LWP::UserAgent;
use POSIX qw(floor strftime);

use lib "/var/www/edastro.com/perl";
use ATOMS qw(btrim epoch2date date2epoch);
use DB qw(rows_mysql db_mysql $print_queries show_queries);

my $db		= 'edastro';
my $timeout	= 30;

$SIG{ALRM} = sub { die "timeout"; };

open HTML, ">/www/edastro.com/catalog/broken-images-tmp.html";
print HTML "<h3>Broken images</h3><p/>Updated: ".epoch2date(time)."<p/>\n";
print HTML "<table>\n";

my $found = 0;

my @rows = db_mysql($db,"select ID,name,topimage,toplocalimage,mainimage,mainimagehidden from poi where deleted is null");
foreach my $r (@rows) {
	my %images = ();

	my $link = $$r{toplocalimage} ? $$r{toplocalimage} : $$r{topimage};
	$link = "https://edastro.com$link" if ($link =~ /^\//);

	$images{$$r{ID}}{$link} = 'POI Form Image' if (!$$r{mainimagehidden});

	my @img = db_mysql($db,"select imagelink,localimage,title,ID from gallery where poiID=? and deleted is null",[($$r{ID})]);
	foreach my $i (@img) {
		my $img = $$i{localimage} ? $$i{localimage} : $$i{imagelink};
		$img = "https://edastro.com$img" if ($img =~ /^\//);
		$images{$$r{ID}}{$img} = $$i{title};
	}

	foreach my $poiID (sort {$a<=>$b} keys %images) {
		foreach my $url (keys %{$images{$poiID}}) {
			my $name = $images{$poiID}{$url};

			next if (!$url);

			my $tmp = '/tmp/broken-image-test-edastro';

			my $ok = 0;
			my $tries = 0;

			while ($tries<3 && !$ok) {
				$tries++;
				my $bytes = 0;

				eval {
					alarm($timeout);
					eval {
						warn "Testing [$tries] $url ($name)\n";
						alarm($timeout);
						unlink $tmp if (-e $tmp);
						$bytes = binaryGET($url,$tmp);
						alarm(0);
					};
					alarm(0);
				};
				$ok = ($bytes || (-e $tmp && (stat($tmp))[7])) ? 1 : 0;
			}
			unlink $tmp if (-e $tmp);

			if (!$ok) {
				print "ERROR: /gec/$poiID ($$r{name}) - $url ($name)\n";

				print HTML "<tr><td align=\"right\">$poiID\&nbsp;\&nbsp;\&nbsp;</td><td><a href=\"/gec/view/$poiID\">$$r{name}</a></td><td>\&nbsp;\&nbsp;\&nbsp;</td><td><a href=\"$url\">$name</a></td></tr>\n";
				$found++;
			}
		}
	}
	
}

print HTML "NONE\n" if (!$found);
print HTML "</table>\n";
close HTML;

system('/usr/bin/mv','/www/edastro.com/catalog/broken-images-tmp.html','/www/edastro.com/catalog/broken-images.html');

exit;



sub binaryGET {
	my $url = shift;
	my $outfile = shift;

	my $ua = LWP::UserAgent->new;
	$ua->agent('Mozilla/5.0');
	my $response = $ua->get($url);

	if ($response->is_success) {
		my $bin_data = $response->decoded_content;
		open DATA, '>:raw', $outfile or return 0;
		print DATA $bin_data;
		close DATA;
		return length($bin_data);
	} else {
		#info("curlGET error [$sessionDATA{username}] ($url): ".$response->status_line);
		return undef;
	}
	return 0;
}

