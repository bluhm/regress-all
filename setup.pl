#!/usr/bin/perl
# setup machine for regress test

use strict;
use warnings;
use File::Basename;
use Getopt::Std;

my %opts;
getopts('h:v', \%opts) or do {
    print STDERR "usage: $0 [-v] -h host\n";
    exit(2);
};
$opts{h} or die "No -h specified";

my $dir = dirname($0);
chdir($dir)
    or die "Chdir to '$dir' failed: $!";

# copy scripts

my @sshcmd = ('ssh', $opts{h}, 'mkdir', '-p', '/root/regress');
system(@sshcmd)
    and die "Command '@sshcmd' failed: $?";

my @scpcmd = ('scp');
push @scpcmd, '-q' unless $opts{v};
(my $host = $opts{h}) =~ s/.*\@//;
push @scpcmd, ("regress.pl", "env-$host.sh", "test.list",
    "$opts{h}:/root/regress");
system(@scpcmd)
    and die "Command '@scpcmd' failed: $?";
