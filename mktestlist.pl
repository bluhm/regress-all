#!/usr/bin/perl
# print the Makefile leaves of the regress directory

use strict;
use warnings;
use File::Find;

find(\&wanted, "/usr/src/regress");

my ($prevdir, $prevname);
sub wanted {
    return unless m{^Makefile$};
    if ($prevdir && $File::Find::dir !~ m{^\Q$prevdir\E/}) {
	print $prevname, "\n";
    }
    ($prevdir, $prevname) = ($File::Find::dir, $File::Find::name);
}
