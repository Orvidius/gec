#!/usr/bin/perl
use strict;
$|=1;

use utf8;
use feature qw( unicode_strings );

use LWP 5.64;
use IO::Socket::SSL;
use JSON;

use lib "perl";
use DB qw(db_mysql rows_mysql);

$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

$ENV{HTTPS_DEBUG} = 1;

IO::Socket::SSL::set_ctx_defaults(
     SSL_verifycn_scheme => 'www',
     SSL_verify_mode => 0,
);

my %fields = (	name=>1,
		galMapSearch=>1,
		galMapUrl=>1,
		type=>1,
		descriptionMardown=>1,
		descriptionHtml=>1,
		coord_x=>1,
		coord_y=>1,
		coord_z=>1
		);

my $ref  = undef;
my $json = JSON->new->allow_nonref;

if (1) {
	my $url	= 'https://www.edsm.net/en/galactic-mapping/json-edd';

	my $browser = LWP::UserAgent->new;
	my $response = $browser->get($url);

	if (!$response->is_success) {
		die "Could not get GMP JSON\n";
	}

	$ref = $json->decode( $response->content );
} else {
	open TXT, "<gmp.json";
	my @lines = <TXT>;
	close TXT;

	$ref = $json->decode( join '', @lines );
}

die "Error retrieving data\n" if (!$ref || ref($ref) ne 'ARRAY');

foreach my $r (@$ref) {
	my %hash = %$r;

	delete($hash{coord_x});
	delete($hash{coord_y});
	delete($hash{coord_z});
	delete($hash{coordinates});

	($hash{coord_x}, $hash{coord_y}, $hash{coord_z}) = (@{$$r{coordinates}});

	foreach my $c (qw(coord_x coord_y coord_z)) {
		$hash{$c} = undef if (!defined($hash{$c}) || ref($hash{$c}));
	}

	$hash{name} = htmlify($hash{name});

	print "$hash{id}: $hash{name} ($hash{coord_x} / $hash{coord_y} / $hash{coord_z}) $hash{galMapSearch}\n";

	my $update = '';
	my @params = ();
	my $vals = '';
	my $vars = '';
	foreach my $k (keys %hash) {
		next if ($k eq 'id' || !$fields{$k});

		push @params, $hash{$k};
		$update .= ",$k=?";
		$vars .= ",$k";
		$vals .= ",?";
	}
	$update =~ s/^,+//s;
	$vars =~ s/^,+//s;
	$vals =~ s/^,+//s;

	push @params, $hash{id};

	my @rows = db_mysql('edastro',"select id from GMP where id=?",[($hash{id})]);
	if (@rows) {
		db_mysql('edastro',"update GMP set $update where id=?",\@params);
	} else {
		db_mysql('edastro',"insert into GMP ($vars,id) values ($vals,?)",\@params);
	}
}


sub htmlify {
	my $string = shift;
	#$string =~ s/\&/\&amp;/gs;
	#$string =~ s/\"/\&quot;/gs;
	#$string =~ s/\</\&lt;/gs;
	#$string =~ s/\>/\&gt;/gs;
	$string = convert_unicode($string);
	return $string;
}

sub convert_unicode {
    use HTML::Entities;
    use Encode;
    my $str = shift;
    Encode::_utf8_off($str);
    return encode_entities(decode('utf8',$str));
}
