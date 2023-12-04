package AUTH;
########################################################################
#
# Copyright (C) 2018, Ed Toton (CMDR Orvidius), All Rights Reserved.

use strict;
use Time::Local;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Net::SMTP;
use CGI::Cookie;
use Sys::Syslog;
use Sys::Syslog qw(:DEFAULT setlogsock);
use POSIX;
use LWP::Simple;
use LWP::UserAgent;
use HTML::Entities;
use JSON;
use HTTP::Request;
use HTTP::Request::Common;


use lib "/www/edastro.com/perl";
use DB qw(rows_mysql db_mysql);
use EMAIL qw(sendMultipart);
use ATOMS qw(btrim);

my @months;
our $sessionID;
our $sessionUserID;
our $usertable;
our $sessiontable;
our $mailfrom;
our $progname;
our %sessionDATA;
our %cookies;
our $cookiename;
our $cookiedomain;

BEGIN { # Export functions first because of possible circular dependancies
   use Exporter;
   use vars qw(@ISA $VERSION @EXPORT_OK);

   $VERSION = 2.01;
   @ISA = qw(Exporter);
   @EXPORT_OK = qw(createUser getSession getCookieSession createSession setCookieSession setCookie getCookie 
			send_verify_email resend_verify_email verify_email verifyPassword setPassword
			getUser getUserData updateEmail getUserID resetPasswordRequest emailExists destroySession
			checkLockout setLockout getSessions getUserFromResetCode invalidateResetCode
			checkAdmin isAdmin verifyAccess accessPriv validate_username validate_email getActiveSessions activeUser
			$sessionUserID $sessionID %sessionDATA info verify_captcha unsubscribe toggle_subscription);

	@months		= ('Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec');

	$sessionID	= '';
	$sessionUserID	= undef;
	$usertable	= 'users';
	$sessiontable	= 'usersessions';

	%sessionDATA	= ();

	$mailfrom	= 'noreply@edastro.com';
	$progname	= 'EDAstro.com';

	%cookies = fetch CGI::Cookie;
	$cookiename	= 'EDAstroSESSION';
	$cookiedomain	= 'edastro.com';

	srand(time()^($$+($$ << 15)));
}

#############################################################################

sub accessPriv {
	my $thing = shift;
	return 0 if (!$sessionUserID || !$sessionID);
	my $access = verifyAccess();
	#info("$sessionUserID: $access/$sessionDATA{verified}/$sessionDATA{admin}, $sessionDATA{privs}");

	return 0 if (!$access);
	return 0 if (!$sessionDATA{verified});
	return 1 if ($sessionDATA{admin});

#	my @list = split /[\|,]+/, $sessionDATA{privs};
#	my %privs = ();
#	foreach my $k (@list) {
#		$privs{$k} = 1;
#	}
#	return 1 if ($privs{$thing});

	return 0;
}

sub checkAdmin {
	my $userID = shift;
	return 0 if (!$userID);

	my @rows = db_mysql('edastro',"select access,admin,verified from $usertable where ID=?",[($userID)]);
	if (@rows) {
		my $r = shift @rows;
		return 0 if (!$$r{verified} || !$$r{admin} || !$$r{access} || $$r{banned});
		return $$r{admin} if ($$r{admin});
	}
	return 0;
}

sub isAdmin {
	my $userID = shift;

	if ($userID && (!$sessionUserID || $userID != $sessionUserID)) {
		return checkAdmin($userID);
	}

	return 0 if (!$sessionUserID || !$sessionID);
	my $access = verifyAccess();
	return 0 if (!$access);
	return 0 if (!$sessionDATA{verified});
	return 0 if ($sessionDATA{banned});
	return $sessionDATA{admin} if ($sessionDATA{admin} || $sessionUserID==1);
	return 0;
}

sub verifyAccess {
	return 0 if (!$sessionUserID || !keys(%sessionDATA));
	return $sessionDATA{access};
}

#############################################################################

sub validate_email {
	my $string = shift;

	return 1 if ($string =~ /^[\w\d\-\_\+\=\.]+\@[\w\d\-\_\+\=\.]+\.[a-zA-Z]{2,10}$/);
	return 0;
}

sub validate_username {
	my $string = btrim(shift);

	return 1 if ($string =~ /^\w+[ \w\d\.\-\_\#]+[\w\d]+$/);
	return 0;
}

#############################################################################


sub createUser {
	my $username = btrim(shift);
	my $email = btrim(shift);
	my $password = shift;
	return 0 if (!$username || !$password || !$email);

	my $code = generate_code(31,'unsubcode');

	my @rows = db_mysql('edastro',"select * from $usertable where username=? or email=?",[($username,$email)]);

	if (!@rows) {
		my $userID =  db_mysql('edastro',"insert into $usertable (username,email,password,created,verified,access,unsubcode) values (?,?,?,NOW(),0,1,?)",
				[($username,$email,md5_hex($password),$code)]);
		info("User created: $username ($userID) $email");
		send_verify_email($userID,$username,$email);
		return $userID;
	}
	return undef;
}

sub setPassword {
	my ($userID,$newPass) = @_;
	return 0 if (!$userID || !$newPass);

	return db_mysql('edastro',"update $usertable set password=? where ID=?",[(md5_hex($newPass),$userID)]);
}

sub checkLockout {
	my $userID = shift;
	
	my @rows = db_mysql('edastro',"select ID from $usertable where ID=? and access>0 and loginLockout is null or NOW()>loginLockout",[($userID)]);
	return 1 if (@rows);
	return 0;
}

sub setLockout {
	my $userID = shift;
	my $seconds = shift;

	db_mysql('edastro',"update $usertable set loginLockout=date_add(NOW(), interval ? second) where ID=?",[($seconds,$userID)]);
	
}

sub verifyPassword {
	my ($userID,$pass) = @_;
	return 0 if (!$userID);

	my @rows = db_mysql('edastro',"select ID from $usertable where ID=? and password=? and access>0",[($userID,md5_hex($pass))]);
	return 1 if (@rows);
	return 0;
}

sub invalidateResetCode {
	my $code = shift;
	return db_mysql('edastro',"update $usertable set resetcode='' where resetcode=?",[($code)]);
}

sub resetPasswordRequest {
	my $username = btrim(shift);
	my %user = getUser($username);
	my $userID = $user{ID};
	my $code = generate_code(31,'resetcode');
	my $email = $user{email};

	return undef if (!$username || !$userID || !$email);

	my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = gmtime(time);
	$year += 1900;
	my $maildate = sprintf("%02u %3s %04u %02u:%02u:%02u -0000",$mday,$months[$month],$year,$hour,$min,$sec);

	my $link = "https://edastro.com/auth/resetpassword?c=$code";

	my $txt = "\nPassword reset requested for $username at $progname! To reset your password, just use the link below (if your mail program doesn't let you click it, just copy and paste it into your web browser's address bar). This link will expire in one hour if you do not use it.\n\n$link\n\n\n";

	my $html = "\nPassword reset requested for $username at $progname! To reset your password, just use the link below. This link will expire in one hour if you do not use it.<p>\n\n<a href=\"$link\">$link</a>";

	my $count = 0;
	while ($count < 10) {
		$count++;
		if (sendMultipart($email,'No-Reply',$mailfrom,'Password Reset Request for EDAstro.com',$txt,$html)) {
			info("Sent password reset email to $username ($userID) $email");
			last;
		}
	}

	return db_mysql('edastro',"update $usertable set resetcode=?,resetexpire=date_add(NOW(), interval 1 hour) where ID=?",[($code,$userID)]);
}

sub unsubscribe {
	my $code = shift;

	my @rows = db_mysql('edastro',"select ID,username,sendemails from $usertable where unsubcode=?",[($code)]);

	foreach my $r (@rows) {
		db_mysql('edastro',"update $usertable set sendemails=0 where ID=?",[($$r{ID})]);
		return $$r{username};
	}
}

sub toggle_subscription {
	my $userID = shift;
	$userID = $sessionUserID if (!$userID);
	return if (!$sessionUserID || !$userID);
	db_mysql('edastro',"update users set sendemails=1-sendemails where ID=?",[($userID)]);
}

sub updateEmail {
	my ($userID,$newEmail) = @_;
	return 0 if (!$userID || !$newEmail);

	my @rows = db_mysql('edastro',"select username,email from $usertable where ID=?",[($userID)]);

	if (@rows && btrim(lc(${$rows[0]}{email})) eq btrim(lc($newEmail))) {
		# Emails are the same, no change.
		return 1;
	} elsif (!@rows) {
		info("updateEmail: Could not retrieve user details: $userID, new email: $newEmail");
		return undef;
	}

	my $ok = db_mysql('edastro',"update $usertable set email=?,verified=0 where ID=?",[($newEmail,$userID)]);
	send_verify_email($userID,${$rows[0]}{username},$newEmail) if ($ok);
	info("updateEmail: Could not send verification email, update failed") if (!$ok);
	return $ok;
}

sub getUserID {
	my $username = shift;
	return 0 if (!$username);

	my %data = getUser($username);
	return $data{ID};
}

sub getUser {
	my $username = shift;

	my @rows = db_mysql('edastro',"select * from $usertable where username=?",[($username)]);
	if (@rows) {
		return %{$rows[0]};
	}

	if ($username =~ /\@/) {
		my @rows = db_mysql('edastro',"select * from $usertable where email=?",[($username)]);
		if (@rows) {
			return %{$rows[0]};
		}
	}

	my %hash = ();
	return %hash;
}
	
sub getUserData {
	my $userID = shift;

	my @rows = db_mysql('edastro',"select * from $usertable where ID=?",[($userID)]);
	if (@rows) {
		return %{$rows[0]};
	}
	my %hash = ();
	return %hash;
}

sub getUserFromResetCode {
	my $code = shift;
	
	my @rows = db_mysql('edastro',"select ID from $usertable where resetcode=?",[($code)]);
	if (@rows) {
		return ${$rows[0]}{ID};
	}
	return undef;
}
	

#############################################################################

sub activeUser {
	if ($sessionUserID && keys %sessionDATA) {
		return $sessionUserID;
	}
	return 0;
}

sub destroySession {
	setCookie($cookiename, '0');
	db_mysql('edastro',"delete from $sessiontable where sessionID=?",[($sessionID)]);
}

sub getActiveSessions {
	my $userID = shift;
	my @rows = db_mysql('edastro',"select $sessiontable.*,username from $sessiontable,$usertable where userID=$usertable.ID order by lastseen desc,created desc");
	return @rows;
}

sub getSessions {
	my $userID = shift;
	my @rows = db_mysql('edastro',"select * from $sessiontable where userID=?",[($userID)]);
	return @rows;
}

sub createSession {
	my $userID = shift;

	my @chars = ("A".."Z","a".."z",0..9,'-','.');
	my $code = '';
	my $ok = 0;

	while (!$ok) {
		$code = join("",@chars[map{rand @chars}(1..63)]);
		my @rows = db_mysql('edastro',"select userID from $sessiontable where sessionID=?",[($code)]);
		$ok = 1 if (!@rows);
	}

	db_mysql('edastro',"insert into $sessiontable (userID,sessionID,created,expiration,ip,browser) values (?,?,NOW(),date_add(NOW(),interval 14 day),?,?)",
			[($userID,$code,$ENV{REMOTE_ADDR},$ENV{HTTP_USER_AGENT})]);
	$ok = getSession($code);
	$sessionID = '';
	$sessionID = $code if ($ok);
	$sessionUserID = undef;
	$sessionUserID = $userID if ($ok);

	info("Session created: $sessionDATA{username} ($userID) $sessionDATA{email} = $sessionID") if ($ok);
	info("Session failed: $userID = $sessionID") if (!$ok);

	return $ok;
}

sub getCookieSession {
	$sessionID = getCookie($cookiename);
	#info("Session Cookie: $sessionID");
	db_mysql('edastro',"update $sessiontable set lastseen=NOW(),expiration=date_add(NOW(),interval 14 day) where sessionID=?",[($sessionID)]);
	return getSession($sessionID);
}

sub getSession {
	my $sessionID = shift;
	%sessionDATA = ();

	return undef if (!$sessionID);

	db_mysql('edastro',"delete from $sessiontable where expiration is null or NOW()>expiration");

	my @rows = db_mysql('edastro',"select * from $usertable,$sessiontable where userID=$usertable.ID and sessionID=? and NOW()<expiration and ip=?",
			[($sessionID,$ENV{REMOTE_ADDR})]);

	if (@rows) {
		my $r = shift @rows;
		%sessionDATA = %$r;
		#info("Session: ($sessionDATA{userID}) $sessionDATA{username} = $sessionID");
		$sessionUserID = $sessionDATA{userID};
		return $sessionUserID;
	}

	return undef;
}

sub setCookieSession {
	setCookie($cookiename, $sessionID);
}

sub setCookie {
	my ($cookie, $value) = @_;

	my $c = new CGI::Cookie(-name => $cookie,
			-value => $value,
			-path => '/',
			-expires => '+1M',
			-samesite => 'Lax',
			-secure  =>  1,
			'-max-age'=>'+1M',
			-domain => $cookiedomain);

	print "Set-Cookie: $c\n";
}

sub getCookie {
	my $cookie = shift;
	my $c = $cookies{$cookie};
	$c =~ s/^$cookie\s*=\s*//;
	$c =~ s/;\s+path=\/.*//;
	return $c;
}


#############################################################################

sub emailExists {
	my $email = shift;

	my @rows = db_mysql('edastro',"select ID from $usertable where email=?",[($email)]);
	return 1 if (@rows);
	return 0;
}

sub verify_email {
	my $code = shift;

	my @rows = db_mysql('edastro',"select ID,username,email from $usertable where verifycode=?",[($code)]);
	if (@rows) {
		# Success

		db_mysql('edastro',"update $usertable set verified=1 where verifycode=?",[($code)]);
		info("Email verified for ${$rows[0]}{username} (${$rows[0]}{ID}) ${$rows[0]}{email} = $code");
		return ${$rows[0]}{ID};
	}
	return 0; # Default to deny
}

sub resend_verify_email {
	my $userID = shift;

	my @rows = db_mysql('edastro',"select * from $usertable where ID=?",[($userID)]);
	if (@rows) {
		send_verify_email($userID,${$rows[0]}{username},${$rows[0]}{email});
		return $userID;
	}
	return undef;
}

sub send_verify_email {
	my $userID = shift;
	my $username = shift;
	my $email = shift;

	my $code = assign_verify_code($userID);

	my ($sec,$min,$hour,$mday,$month,$year,$wday,$yday,$isdst) = gmtime(time);
	$year += 1900;
	my $maildate = sprintf("%02u %3s %04u %02u:%02u:%02u -0000",$mday,$months[$month],$year,$hour,$min,$sec);

	my $link = "https://edastro.com/auth/verifyemail?c=$code";

	my $txt = "\nThank you $username, for signing up for $progname! To verify your email address, just use the link below (if your mail program doesn't let you click it, just copy and paste it into your web browser's address bar):\n\n$link\n\n\n";

	my $html = "\nThank you $username, for signing up for $progname! To verify your email address, just use the link below:<p>\n\n<a href=\"$link\">$link</a>";

	my $count = 0;
	while ($count < 10) {
		$count++;
		if (sendMultipart($email,'No-Reply',$mailfrom,'Welcome to EDAstro!',$txt,$html)) {
			info("Sent email verification to $username ($userID) $email");
			last;
			return $count;
		}
	}
}

sub assign_verify_code {
	my $userID = shift;
	my $code = generate_code(31,'verifycode');
	db_mysql('edastro',"UPDATE $usertable SET verifycode=? WHERE ID=?",[($code,$userID)]);
	return $code;
}

sub generate_code {
	my $length = shift;
	my $column = shift;

	$length = 31 if (!$length);
	my $code = '1234';

	my @chars = ("A".."Z","a".."z",0..9,'-','.');

	my $ok = 0;
	while (!$ok) {
		$code = join("",@chars[map{rand @chars}(1..31)]);
		my @rows = db_mysql('edastro',"SELECT ID FROM $usertable WHERE $column=?",[($code)]);
		$ok = 1 if (!@rows);
	}

	return $code;
}

#############################################################################


sub verify_captcha {
	my $resp = shift;
	my $url = 'https://www.google.com/recaptcha/api/siteverify';

	open DATA, "</www/EDtravelhistory/captcha-secret";
	my $secret = <DATA>;
	chomp $secret;
	close DATA;

	my %data = (secret=>$secret, response=>$resp, remoteip=>$ENV{REMOTE_ADDR});

	my $ua = LWP::UserAgent->new(timeout => 10);
	my $request = HTTP::Request::Common::POST( $url, [ %data ] );
	my $response = $ua->request($request);

	if ( $response->is_success() ) {
		if (0) {
			my $href = JSON->new->utf8->decode($response->decoded_content);
			my $TF = $$href{success} ? 'true' : 'false';
			print "Content-Type: text/plain\n\n".$response->decoded_content."\n\n$TF\n"; exit;
		}

		my $ok = 0;
		eval {
			my $href = JSON->new->utf8->decode($response->decoded_content);
			my $TF = $$href{success} ? 'true' : 'false';
			$ok = 1 if ($href && ref($href) eq 'HASH' && $TF eq 'true');
		};
		return $ok;
	} else {
		info(" ERROR: " . $response->status_line().' - '.$response->decoded_content);
	}
	return 0;
}


sub info {
	foreach my $message (@_) {
		chomp $message;
		$message =~ s/(\^M)?\s*$//;

		next if ($message =~ /^\s*$/s);

		setlogsock('unix');

		my $script = $0;
		$script =~ s/^.*\///s;
		$script =~ s/\s+.*$//s;

		openlog($script,"pid","user");
		syslog("info","$message");
		closelog();
		#print "$message\n";
  	}
}

#############################################################################

1;
