#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();

my %opts;
getopts('v', \%opts);

# get test list from command line or input file
my @tests;
if (@ARGV) {
    @tests = @ARGV;
} else {
    open(my $tl, '<', "test.list")
	or die "Open 'test.list' for reading failed: $!";
    chomp(@tests = <$tl>);
    close($tl)
	or die "Close 'test.list' after reading failed: $!";
}

# run sudo is if is set to get password in advance
my $sudocmd = "make -s -f - sudo";
open(my $sudo, '|-', $sudocmd)
    or die "Open pipe to '$sudocmd' failed: $!";
print $sudo "sudo:\n\t\${SUDO} true\n";
close($sudo) or die $! ?
    "Open pipe to '$sudocmd' failed: $!" :
    "Command '$sudocmd' failed: $!";

sub bad($$$) {
    my ($test, $reason, $meassge) = @_;
    print $tr "$reason\t$test\t$meassge\n";
    no warnings 'exiting';
    next;
}

sub good($) {
    my ($test) = @_;
    print $tr "PASS\t$test\n";
}

# run make regress for each test
foreach my $test (@tests) {
    my $dir = $test =~ m,^/, ? $test : "/usr/src/regress/$test";
    chdir($dir)
	or bad $test, 'NOEXITS', "Chdir to $dir failed: $!";

    my $cleancmd = "make clean";
    $cleancmd .= " >/dev/null" unless $opts{v};
    $cleancmd .= " 2>&1";
    system($cleancmd)
	and bad $test, 'NOCLEAN', "Command '$cleancmd' failed: $!";

    # write make output into log file
    my $makelog = "make.log";
    $makelog = "obj/$makelog" if -d "obj";
    open(my $log, '>', $makelog)
	or bad $test, 'NOLOG', "Open '$makelog' for writing failed: $!";

    my @errors;
    my $runcmd = "make regress 2>&1";
    open(my $out, '-|', $runcmd)
	or bad $test, 'NORUN', "Open pipe from '$runcmd' failed: $!";
    my $prev = "";
    while (<$out>) {
	print if $opts{v};
	print $log $_;
	push @errors, $prev, if /^FAILED$/;
	chomp($prev = $_);
    }
    close($out)
	or bad $test, 'NORESULT', $! ?
	"Close pipe from '$runcmd' failed: $!" :
	"Command '$runcmd' failed: $?";
	
    close($log)
	or bad $test, 'NOLOG', "Close '$makelog' after writing failed: $!";

    bad $test, 'FAIL', join(", ", @errors) if @errors;
    good $test;
}

close($tr)
    or die "Close 'test.result' after writing failed: $!";
