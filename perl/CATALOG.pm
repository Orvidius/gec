package CATALOG;
########################################################################
#
# Copyright (C) 2022, Ed Toton (CMDR Orvidius), All Rights Reserved.

use strict;
use Time::Local;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Net::SMTP;
use CGI::Cookie;
use Sys::Syslog;
use Sys::Syslog qw(:DEFAULT setlogsock);
use POSIX;

use lib "/www/edastro.com/perl";
use DB qw(rows_mysql db_mysql);
use EMAIL qw(sendMultipart);
use ATOMS qw(btrim epoch2date date2epoch);

my @months;

BEGIN { # Export functions first because of possible circular dependancies
   use Exporter;
   use vars qw(@ISA $VERSION @EXPORT_OK);

   $VERSION = 2.01;
   @ISA = qw(Exporter);
   @EXPORT_OK = qw(
		);

	@months		= ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');
}

#############################################################################


#############################################################################

1;
