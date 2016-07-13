#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";

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
    print $tr join("\t", @_);
    no warnings 'exiting';
    next;
}

sub good($) {
    print $tr join("\t", @_);
}

# run make regress for each test
foreach my $test (@tests) {
    my $dir = $test =~ m,^/, ? $test : "/usr/src/regress/$test";
    chdir($dir)
	or bad $test, 'NOTEST', "Chdir to $dir failed: $!";

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

    my $runcmd = "make regress 2>&1";
    open(my $out, '-|', $runcmd)
	or bad $test, 'NORUN', "Open pipe from '$runcmd' failed: $!";
    while (<$out>) {
	print if $opts{v};
	print $log $_;
    }
    close($out)
	or bad $test, 'NORESULT', $! ?
	"Close pipe from '$runcmd' failed: $!" :
	"Command '$runcmd' failed: $?";
	
    close($log)
	or bad $test, 'NOLOG', "Close '$makelog' after writing failed: $!";

    good $test;
}

close($tr)
    or die "Close 'test.result' after writing failed: $!";
