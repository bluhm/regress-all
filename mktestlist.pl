#!/usr/bin/perl
# print the Makefile leaves of the regress directory

use strict;
use warnings;
use File::Find;

find(\&wanted, "/usr/src/regress");

my $prevdir;
sub wanted {
    return unless m{^Makefile$};
    if ($prevdir && $File::Find::dir !~ m{^\Q$prevdir\E/}) {
	$prevdir =~ s{^/usr/src/regress/}{};
	print $prevdir, "\n";
    }
    $prevdir = $File::Find::dir;
}
