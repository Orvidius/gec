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

if (!@ARGV) {
	open HTML, ">/www/edastro.com/catalog/broken-images-tmp.html";
	print HTML "<h3>Broken images</h3><p/>Updated: ".epoch2date(time)."<p/>\n";
	print HTML "<table>\n";
}

my $found = 0;

my @rows = db_mysql($db,"select ID,name,topimage,toplocalimage,mainimage,mainimagehidden from poi where deleted is null");
foreach my $r (@rows) {
	my %images = ();

	next if ($ARGV[0] && $$r{ID} != $ARGV[0]);

	my $desc = '';
	my @data = db_mysql($db,"select description from poidata where poiID=?",[($$r{ID})]);
	if (@data) {
		$desc = ${$data[0]}{description};
	}

	my $link = $$r{toplocalimage} ? $$r{toplocalimage} : $$r{topimage};
	$link = "https://edastro.com$link" if ($link =~ /^\//);

	$images{$$r{ID}}{$link} = 'POI Form Image' if (!$$r{mainimagehidden});

	my @img = db_mysql($db,"select imagelink,localimage,title,ID from gallery where poiID=? and deleted is null",[($$r{ID})]);
	foreach my $i (@img) {
		my $img = $$i{localimage} ? $$i{localimage} : $$i{imagelink};
		$img = "https://edastro.com$img" if ($img =~ /^\//);
		$images{$$r{ID}}{$img} = $$i{title};
	}

	while ($desc =~ /\((https?:\/\/([^\)]+\.(jpg|png|gif)(\?[^\)*])?))\)/ig) {
		my $img = $1;
		$img = "https://edastro.com$img" if ($img =~ /^\//);
		#print "Test: $img\n";
		$images{$$r{ID}}{$img} = $img;
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

				print HTML "<tr><td align=\"right\">$poiID\&nbsp;\&nbsp;\&nbsp;</td><td><a href=\"/gec/view/$poiID\">$$r{name}</a></td><td>\&nbsp;\&nbsp;\&nbsp;</td><td><a href=\"$url\">$name</a></td></tr>\n" if (!@ARGV);
				$found++;
			}
		}
	}
	
}

if (!@ARGV) {
	print HTML "NONE\n" if (!$found);
	print HTML "</table>\n";
	close HTML;

	system('/usr/bin/mv','/www/edastro.com/catalog/broken-images-tmp.html','/www/edastro.com/catalog/broken-images.html');
}

exit;


sub binaryGET {
	my $url = shift;
	my $outfile = shift;
	my $retry = shift;
	my $tag = shift;

	my $referer = '';
	my $host = '';

	if ($url =~ /^https?:\/\/([\w\d\-\.]+)\//) {
		$host = $1;
	}

	my $ua = LWP::UserAgent->new;
	#$ua->agent('Mozilla/5.0');
	$ua->agent("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/109.0");

	if ($url =~ /^(https:\/\/i\.postimg\.cc\/[\w\d]+)\//i) {
		$referer = $1;
		#$url .= "?dl=1" if ($url !~ /dl=1$/);
	}
	$referer = 'https://edastro.com' if (!$referer);

	if ($url =~ /^https:\/\/media\.discordapp\.net\/attachments\/\d+\/\d+\/\S+?\.(png|gif|jpg|jpeg)\?.+/) {
		$url =~ s/\?.+$//s;
	}

	#my $response = $ua->get($url, "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", Referer=>$referer, Host=>$host);
	my $response = $ua->get($url, "Accept"=>"image/webp,image/jpeg,image/png,image/gif,*/*", Referer=>$referer, Host=>$host,
		"Cache-Control"=>"no-cache", Pragma=>"no-cache", "Sec-Fetch-Dest"=>"image", "Sec-Fetch-Mode"=>"no-cors", "Sec-Fetch-Site"=>"same-site");

	if ($response->is_success) {
		my $bin_data = $response->decoded_content;
		open DATA, '>:raw', $outfile or return 0;
		print DATA $bin_data;
		close DATA;
		return length($bin_data);
	} elsif ($response->status_line =~ /^429/ && $url =~ /^(https?:\/\/(i\.)?imgur\.com\/([\w\d]+\.(png|jpg|jpeg|gif)))(\?\S+)?$/i) {
		my ($link, $i, $fn, $ext) = ($1, $2, $3, $4);
		print "FAIL: $url (".$response->status_line.")\n";
		#my $exec = "( /usr/bin/ssh -p 222 www\@reaper.necrobones.net 'curl $link' > $outfile ) 2>\&1";

		$link =~ s/\/imgur.com\//\/i.imgur.com\//s if (!$i);

		my $exec = "/usr/bin/ssh -p 222 www\@reaper.necrobones.net 'curl $link' > $outfile 2>/dev/null";
		#info($exec);
		#info(split /[\r\n]+/s, `$exec`);
		system($exec);
		return (stat($outfile))[7];
	} else {

		if ($url =~ /^(https?:\/\/[\w\-\.\/]+\.(png|jpg|gif))$/) {
			unlink $outfile if (-e $outfile);
			system('/usr/bin/curl','-o',$outfile,$url);
			if (-e $outfile) {
				return (stat($outfile))[7];
			}
		}

		print "FAIL: $url (".$response->status_line.")\n";
		return undef;
	}
	return 0;
}

sub binaryGET_orig {
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

