#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;
use Getopt::Std;
use POSIX;

my %opts;
getopts('h:v', \%opts) or do {
    print STDERR "usage: $0 [-v] -h host\n";
    exit(2);
};
$opts{h} or die "No -h specified";

# create directory for this test run with timestamp 2016-07-13T12:30:42Z
my $date = strftime("%FT%TZ", gmtime);

my $dir = dirname($0). "/..";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
$dir = "results";
-d $dir || mkdir $dir
    or die "Make result directory '$dir' failed: $!";
$dir .= "/$date";
mkdir $dir
    or die "Make directory '$dir' failed: $!";

# setup remote machines

# run regress there

my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/github/regress-all/regress.pl',
    '-e/root/bin/ot-regress');
push @sshcmd, '-v' if $opts{v};
system(@sshcmd)
    and die "Command '@sshcmd' failed: $?";

# get result and logs

my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, ("$opts{h}:/root/github/regress-all/test.*", $dir);
system(@scpcmd)
    and die "Command '@scpcmd' failed: $?";

open(my $tr, '<', "$dir/test.result")
    or die "Open '$dir/test.result' for reading failed: $!";
mkdir "$dir/logs"
    or die "Make directory '$dir/logs' failed: $!";
chdir("$dir/logs")
    or die "Chdir to '$dir/logs' failed: $!";
my @paxcmd = ('pax', '-rzf', "../test.logs", '-s,/obj/make.log,/make.log,');
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

# create html output

chdir($dir)
    or die "Chdir to '$dir' failed: $!";
my @htmlcmd = "bin/html.pl"
system(@htmlcmd)
    and die "Command '@htmlcmd' failed: $?";
