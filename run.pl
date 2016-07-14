#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;
use Getopt::Std;
use POSIX;

my %opts;
getopts('h:', \%opts) or do {
    print STDERR "usage: $0 -h host\n";
    exit(2);
};
$opts{h} or die "No -h specified";

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $date = strftime("%FT%TZ", gmtime);

my $dir = dirname($0);
chdir($dir)
    or die "Chdir to $dir failed: $!";
$dir = "results";
-d $dir || mkdir $dir
    or die "Make result directory '$dir' failed: $!";
$dir .= "/$date";
mkdir $dir
    or die "Make directory '$dir' failed: $!";

# setup remote machines

# run regress there

my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/github/regress-all/regress.pl',
    '-v', '-e/root/bin/ot-regress');
system(@sshcmd)
    and die "Command '@sshcmd' failed: $?";

# get result and log

my @scpcmd = ('scp', "$opts{h}:/root/github/regress-all/test.*", $dir);
system(@scpcmd)
    and die "Command '@scpcmd' failed: $?";

open(my $tr, '<', "$dir/test.result")
    or die "Open '$dir/test.result' for reading failed: $!";
my @paxcmd = ('pax', '-rzf', "$dir/test.logs");
open(my $pax, '|-', @paxcmd)
    or die "Open pipe to '@paxcmd' failed: $!";
while (<$tr>) {
    my ($status, $test, $message) = split(" ", $_, 3);
    print $pax "$test/make.log" unless $test =~ m,[^\w/],;
}
close($pax) or die $! ?
    "Close pipe to '@paxcmd' failed: $!" :
    "Command '@paxcmd' failed: $?";
close($tr)
    or die "Close '$dir/test.result' after reading failed: $!";
