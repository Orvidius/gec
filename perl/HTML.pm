package HTML;

use lib ".";
use ATOMS qw(epoch2date date2epoch);

BEGIN { # Export functions first because of possible circular dependancies
   use Exporter;
   use vars qw(@ISA $VERSION @EXPORT_OK);

   $VERSION = 2.01;
   @ISA = qw(Exporter);
   @EXPORT_OK = qw( print_html color_print yellow_print red_print green_print);

}

#############################################################################


sub print_html {
	my $fn = shift;
	my $hd = shift;
	my $return_instead = shift;
	my $html = '';

	open HTML, "<$fn";
	my @lines = <HTML>;
	close HTML;

	foreach my $line (@lines) {
		if ($line =~ /<!--#include\s+virtual="(\S+)"\s+-->/) {
			my $link = $1;
			if ($link =~ /\.cgi/) {
				$link =~ s/\s//gs;
				$link = "/www/edastro.com$link" if ($link =~ /^\//);
				$html .= `$link x`;
			} else { 
				$html .= retrieve_html($link,$hd);
			}
		} else {
			if ($line =~ /<\/head>/i) {
				$html .= $hd;
			}
			$html .= $line;
		}
	}

	if (!$return_instead) {
		print $html;
	}
	
	return $html;
}

sub retrieve_html {
	my $fn = shift;
	my $hd = shift;
	my $file = '';

	my $path = $0;
	$path =~ s/\/[^\/]+$//;

	return if ($fn =~ /^\./);

	if ($fn !~ /\//) {
		$file = "$path/$fn";
	} elsif ($fn =~ /^\//) {
		if ($path =~ /^((\/var)?\/www\/[\w\d\_\.]+)\//) {
			$file = "$1$fn";
		} else {
			return;
		}
	} else {
		return;
	}

	if ($file && -e $file) {
		return print_html($file,$hd,1);
	}
}

sub color_print {
	my $color = shift;
	my $string = join('',@_);
	my $space = '';

	if ($string =~ /^(.*\S)(\s+)$/s) {
		$string = $1;
		$space = $2;
	} else {
		$space = ' ';
	}


	print "<font color=\"$color\">$string</font>$space";
}

sub green_print {
	color_print('#0D0',@_);
}

sub red_print {
	color_print('#E00',@_);
}

sub yellow_print {
	color_print('#EE0',@_);
}

#############################################################################

1;

