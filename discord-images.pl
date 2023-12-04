#!/usr/bin/perl
use strict; $|=1;

use utf8;
use feature qw( unicode_strings );

#use CGI::Carp qw(fatalsToBrowser);

use HTML::Entities;
use Encode;
use CGI;
use JSON;
use LWP::Simple;
use LWP::UserAgent;
use POSIX qw(floor strftime);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Basename;
use File::Copy;

use lib "perl";
use ATOMS qw(btrim epoch2date date2epoch);
use DB qw(rows_mysql db_mysql $print_queries show_queries);

my $update_descriptions	= 0;

my $force		= 0;

my $db			= 'edastro';
my $webpath		= '/poiimages';
my $sitepath		= "/www/edastro.com";
my $filepath		= "$sitepath$webpath";

my $count = 0;

my @t = localtime();

my $year = $t[5]+1900;
my $month = sprintf("%02u",$t[4]+1);
my $day = sprintf("%02u",$t[3]);

my @do_list = ();

foreach my $arg (@ARGV) {
	push @do_list, $arg if ($arg =~ /^\d+$/);
}

my $and = '';

if (@do_list) {
	$and = " and poiID in (".join(',',@do_list).")";
}

my @rows = db_mysql($db,"select poidata.*,poi.name from poidata,poi where description like '\%discord\%' and poiID=poi.ID and deleted is null $and");
foreach my $r (@rows) {
	print "$$r{poiID}: $$r{name}\n";
	my $orig_description = $$r{description};

	my $skip = 0;


	while ($$r{description} =~ /((\]\()([^\s\)]+(discordapp\.net|discordapp\.com)[^\s\)]+)( "|\)))/s) {
		my ($pattern, $pre, $url, $domain, $post) = ($1, $2, $3, $4, $5);

		if ($url =~ /^\/\/[\w\.]+\.(net|com|org)\//) {
			$url = "http:$url";
		}

		print "\t^ $url\n";

		my $ext = get_ext($url);
		my $newext = $ext =~ /^gif$/i ? 'gif' : 'jpg';

		# Default file name and location:
		my $path = "$filepath/$year/$month";
		my $fn = "$year-$month-$day-".md5_hex($url).'.'.$newext;
		my $file = "$path/$fn";
		my $newlink = "$webpath/$year/$month/$fn";

		system("/usr/bin/mkdir -p $path; /usr/bin/chown www:www $path") if (!-d $path);

		# Check for DB entry:
		my @data = db_mysql($db,"select * from poiimages where imagelink=?",[($url)]);
		if (@data) {
			$newlink = ${$data[0]}{localimage};
			$fn = basename($newlink);
			$file = "$sitepath$newlink";
		}

		#if (!-e $file || !(stat($file))[7] || (stat($file))[7] > 10485760 || $force) {
		if (!-e $file || !(stat($file))[7] || $force) {
			# Curl here
			my $safe_url = $url;
			$safe_url =~ s/[^\w\d\.\-\_\+\?\&\(\)\!\@\#\%\*:\\\/]//gs;	# Strip dangerous things
			#$safe_url =~ s/([\+\?\&\(\)\!\@\#\%\*])/\\$1/gs;

			my $temp = "/tmp/$$.$ext";
			warn "# curl -o $temp $safe_url\n";
			system("/usr/bin/curl","-o",$temp,$safe_url);

			if (-e $temp && (stat($temp))[7]) {
				if (lc($ext) ne 'gif') {
					system("/usr/bin/convert",$temp,"-resize","800x800","-quality","90",$file);
				} else {
					move($temp,$file);
				}
			}
			unlink $temp if (-e $temp);
		}

		if (!@data) {
			db_mysql($db,"insert into poiimages (poiID,created,imagelink,localimage) values (?,now(),?,?)",[($$r{poiID},$url,$newlink)]);
		}

		$count ++;
		$$r{description} =~ s/\Q$pattern\E/$pre$newlink$post/gs;

		if (!-e $file || !(stat($file))[7]) {
			$skip = 1;
		}
		
	}

	if (!$skip && $update_descriptions && $orig_description ne $$r{description}) {
		#print "\n$$r{description}\n";

		db_mysql($db,"update poidata set description=? where poiID=?",[($$r{description},$$r{poiID})]);
		system("/www/edastro.com/catalog/poi reformatone $$r{poiID} > /dev/null 2>\&1");

		print "\t^^^ DESCRIPTION UPDATED\n";
		#last;
	} elsif ($orig_description ne $$r{description}) {
		#print "\n$$r{description}\n";
	}

	#last;
}

sub get_ext {
	my $link = shift;

	$link =~ s/^.*https?:\/\///s;
	$link =~ s/\s.*$//s;
	$link =~ s/\#.*$//s;
	$link =~ s/\?.*$//s;

	my @items = reverse(split(/\./,$link));
	return $items[0];
}


