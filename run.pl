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

my $dir = dirname($0). "/results";
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
my @scpcmd = ('scp', "$opts{h}:/root/github/regress-all/test.result", $dir);
system(@scpcmd)
    and die "Command '@scpcmd' failed: $?";

# convert all results to html

my @results = sort glob("results/*/test.result");

my (%t, %d);
foreach my $result (@results) {
    my ($date) = $result =~ m,results/(.+)/test.result,;
    $d{$date} = 1;
    open(my $fh, '<', $result)
	or die "Open '$result' for reading failed: $!";
    while (<$fh>) {
	my ($status, $test, $message) = split(" ", $_, 3);
	my $severity =
	    $status eq 'PASS' ? 1 :
	    $status eq 'FAIL' ? 2 :
	    $status eq 'NOEXIT' ? 3 :
	    $status eq 'NOTERM' ? 4 : 5;
	$t{$test}{$date}
	    and warn "Duplicate test '$test' at date '$date'";
	$t{$test}{$date} = {
	    status => $status,
	    message => $message
	};
	$t{$test}{severity} = ($t{$test}{severity} || 0) * .5 + $severity;
    }
    close($fh)
	or die "Close '$result' after reading failed: $!";
}

my @dates = sort keys %d;
print "test\\date", map {"\t$_" } @dates, "\n";
foreach my $test (sort { $t{$a}{severity} <=> $t{$b}{severity} } keys %t) {
    print "$test";
    foreach my $date (@dates) {
	my $status = $t{$test}{$date}{status};
	print "\t$status";
    }
    print "\n";
}
