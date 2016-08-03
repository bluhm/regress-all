#!/usr/bin/perl

use strict;
use warnings;
use Cwd;
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
my $regressdir = getcwd();
$dir = "results";
-d $dir || mkdir $dir
    or die "Make result directory '$dir' failed: $!";
$dir .= "/$date";
mkdir $dir
    or die "Make directory '$dir' failed: $!";

# setup remote machines

my @setupcmd = ("bin/setup.pl", '-h', $opts{h}, '-d', $date);
push @setupcmd, '-v' if $opts{v};
system(@setupcmd)
    and die "Command '@setupcmd' failed: $?";

my ($user, $host) = split('@', $opts{h}, 2);
while (1) {
    my $version = "$dir/version-$host.txt";
    next if -f $version;
    my $h = "$user\@$host";
    system("ssh $h sysctl kern.version >$version 2>/dev/null")
	and last;
    $host++;
}

# run regress there

($host = $opts{h}) =~ s/.*\@//;
my @sshcmd = ('ssh', $opts{h}, 'perl', '/root/regress/regress.pl',
    '-e', "/root/regress/env-$host.sh");
push @sshcmd, '-v' if $opts{v};
system(@sshcmd)
    and die "Command '@sshcmd' failed: $?";

# get result and logs

my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
push @scpcmd, ("$opts{h}:/root/regress/test.*", $dir);
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

$dir = $regressdir;
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

my @htmlcmd = "bin/setup-html.pl -d $date";
system(@htmlcmd)
    and die "Command '@htmlcmd' failed: $?";

@htmlcmd = "bin/regress-html.pl";
system(@htmlcmd)
    and die "Command '@htmlcmd' failed: $?";
