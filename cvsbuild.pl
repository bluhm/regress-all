#!/usr/bin/perl
# recompile parts of machine for performance comparison

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

use strict;
use warnings;
use Cwd;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;
use Machine;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('D:h:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] [-D cvsdate] -h host
    -d date	set date string and change to sub directory
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -v		verbose
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
my $date = $opts{d};
my $cvsdate = $opts{D};

my $performancedir = dirname($0). "/..";
chdir($performancedir)
    or die "Chdir to '$performancedir' failed: $!";
$performancedir = getcwd();
my $resultdir = "$performancedir/results";
$resultdir .= "/$date" if $date;
$resultdir .= "/$cvsdate" if $cvsdate;
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "cvsbuild-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' started at $date\n");

createhost($user, $host);

get_version();
update_cvs(undef, $cvsdate, "sys");
make_kernel();
reboot();
get_version();

# finish build log

$date = strftime("%FT%TZ", gmtime);
logmsg("script '$scriptname' finished at $date\n");
