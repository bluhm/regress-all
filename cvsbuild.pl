#!/usr/bin/perl
# recompile parts of machine for performance comparison

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
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
use Date::Parse;
use File::Basename;
use Getopt::Std;
use POSIX;

use lib dirname($0);
use Logcmd;
use Machine;
use Buildquirks;

my $scriptname = "$0 @ARGV";

my %opts;
getopts('d:D:h:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] [-d date] [-D cvsdate] -h host [kernel ...]
    -d date	set date string and change to sub directory
    -D cvsdate	update sources from cvs to this date
    -h host	root\@openbsd-test-machine, login per ssh
    -v		verbose
    align	relink kernel aligning all object at page size, no randomness
    gap		relink kernel sorting object files, but use random gap
    sort	relink kernel sorting object files at fixed position
    reorder	relink kernel using the reorder kernel script
    reboot	reboot, this is always done
EOF
    exit(2);
};
$opts{h} or die "No -h specified";
!$opts{d} || str2time($opts{d})
    or die "Invalid -d date '$opts{d}'";
my $date = $opts{d};
!$opts{D} || str2time($opts{D})
    or die "Invalid -D cvsdate '$opts{D}'";
my $cvsdate = $opts{D};

my %allmodes;
@allmodes{qw(align gap sort reorder reboot)} = ();
my %kernelmode = map {
    die "Unknown kernel mode: $_" unless exists $allmodes{$_};
    $_ => 1;
} @ARGV;

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
$performdir = getcwd();
my $resultdir = "$performdir/results";
$resultdir .= "/$date" if $date;
$resultdir .= "/$cvsdate" if $date && $cvsdate;
chdir($resultdir)
    or die "Chdir to '$resultdir' failed: $!";

my ($user, $host) = split('@', $opts{h}, 2);
($user, $host) = ("root", $user) unless $host;

createlog(file => "cvsbuild-$host.log", verbose => $opts{v});
$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' started at $date.\n");

createhost($user, $host);

my %sysctl = get_version();
my $before;
if ($sysctl{'kern.version'} =~
    /#cvs : D(\d{4}).(\d\d).(\d\d).(\d\d).(\d\d).(\d\d):/) {
    $before = "$1-$2-${3}T$4:$5:${6}Z";
} elsif ($sysctl{'kern.version'} =~
    /: (\w{3} \w{3}  ?\d?\d \d\d:\d\d:\d\d \w+ \d{4})\n/) {
    $before = $1;
}
if ($before) {
    my %q = quirks($before, $cvsdate);
    if (keys %q) {
	open(my $fh, '>', "quirks-$host.txt")
	    or die "Open 'quirks-$host.txt' for writing failed: $!";
	print $fh map { "$q{$_}{date} $q{$_}{comment}\n" } sort keys %q;
    }
    foreach my $cmd (quirk_commands($before, $cvsdate, \%sysctl)) {
	if ($cmd eq "reboot") {
	    reboot();
	} else {
	    logcmd('ssh', "$user\@$host", $cmd);
	}
    }
}

update_cvs(undef, $cvsdate, "sys") if $cvsdate;
make_kernel();
if ($kernelmode{align}) {
    align_kernel();
} elsif ($kernelmode{gap}) {
    gap_kernel();
} elsif ($kernelmode{sort}) {
    sort_kernel();
}
reorder_kernel() if $kernelmode{align} || $kernelmode{gap} ||
    $kernelmode{sort} || $kernelmode{reorder};
get_bsdnm();
reboot();
get_version();

# finish build log

$date = strftime("%FT%TZ", gmtime);
logmsg("Script '$scriptname' finished at $date.\n");
