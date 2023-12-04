#!/usr/bin/perl
use strict;

##########################################################################

use CGI;
use Gravatar::URL;

use lib "../perl";
use AUTH qw(%sessionDATA $sessionID getCookieSession setCookieSession createSession verifyPassword getUserID);
use HTML qw(print_html red_print);

##########################################################################

#print "Content-Type: text/html\n\n";


my $q = new CGI;
print $q->header if (!@ARGV || $ARGV[0] ne 'x');

my $userID = getCookieSession();

my $html = '';

$html .= "<a class=\"presence\" href=\"/auth/account\">" if ($userID);
$html .= "<a class=\"presence\" href=\"/auth/login\">" if (!$userID);
$html .= "<div class=\"accountcorner\">\n";

if ($userID) {
	my $avatar = '';
	$avatar = gravatar_url( email => $sessionDATA{email}, rating=>'pg', size=>48, default=>'https://edastro.com/images/account-icon-green-48px.png') 
		if ($sessionDATA{email});
	my $url = $avatar ? $avatar : '/images/account-icon-green-48px.png';

	$html .= "$sessionDATA{username}\n";
	#$html .= "<img src=\"/images/account-icon-green-48px.png\" class=\"borderless\" style=\"vertical-align:middle\">\n";
	$html .= "<img src=\"$url\" class=\"accountcornerImage\" style=\"vertical-align:middle\">\n";
} else {
	$html .= "<img src=\"/images/account-icon-grey-48px.png\" class=\"borderless\" style=\"vertical-align:middle\">\n";
}

$html .= "</div>\n";
$html .= "</a>\n";

print $html;
exit;


##########################################################################


