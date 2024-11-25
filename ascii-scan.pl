#!/usr/bin/perl
use strict;

##########################################################################

#use CGI::Carp qw(fatalsToBrowser);

use utf8;
#use utf8::all;
use feature qw( unicode_strings );

use HTML::Entities;
use Encode;
use CGI;
use JSON;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Headers;
use Text::Markdown 'markdown';
use POSIX qw(floor strftime);
use Tie::IxHash;
use WebService::Discord::Webhook;
use Gravatar::URL;
use MIME::Base64;
use File::Copy;
use Data::Dumper;
#use Text::Unidecode;

use lib "perl";
use ATOMS qw(make_csv parse_csv btrim epoch2date date2epoch);
use DB qw(rows_mysql db_mysql $print_queries show_queries);
use EMAIL qw(sendMultipart);
use AUTH qw(info $sessionUserID %sessionDATA $sessionID getCookieSession setCookieSession getUserID 
                getSessions getActiveSessions accessPriv checkAdmin isAdmin activeUser getUserData );
use HTML qw(print_html red_print);


die "Usage: $0 <poiID>\n" if (!@ARGV);

foreach my $poiID (@ARGV) {
	my @rows = db_mysql('edastro','select * from poidata where poiID=?',[($poiID)]);

	foreach my $r (@rows) {
		my @array = ( $$r{description} =~ m/./g );
		foreach my $c (@array) {
			printf("%s -- %4x\n",$c,ord($c));
		}
	}
}
