#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;
use POSIX;

my %opts;
getopts('e:t:v', \%opts) or do {
    print STDERR "usage: $0 [-v] [-e environment] [-t timeout]\n";
    exit(2);
};
my $timeout = $opts{t} || 10*60;
environment($opts{e}) if $opts{e};

# write summary of results into result file
open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";
$tr->autoflush();

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

sub bad($$$;$) {
    my ($test, $reason, $meassge, $log) = @_;
    print $log "\n$reason\t$test\t$meassge\n" if $log;
    print "\n$reason\t$test\t$meassge\n\n" if $opts{v};
    print $tr "$reason\t$test\t$meassge\n";
    no warnings 'exiting';
    next;
}

sub good($;$) {
    my ($test, $log) = @_;
    print $log "\nPASS\t$test\n" if $log;
    print "\nPASS\t$test\n\n" if $opts{v};
    print $tr "PASS\t$test\n";
}

# run make regress for each test
foreach my $test (@tests) {
    my $dir = $test =~ m,^/, ? $test : "/usr/src/regress/$test";
    chdir($dir)
	or bad $test, 'NOEXIST', "Chdir to $dir failed: $!";

    my $cleancmd = "make clean";
    $cleancmd .= " >/dev/null" unless $opts{v};
    $cleancmd .= " 2>&1";
    system($cleancmd)
	and bad $test, 'NOCLEAN', "Command '$cleancmd' failed: $?";

    # write make output into log file
    my $makelog = "make.log";
    $makelog = "obj/$makelog" if -d "obj";
    open(my $log, '>', $makelog)
	or bad $test, 'NOLOG', "Open '$makelog' for writing failed: $!";

    my @errors;
    my $runcmd = "make regress";
    defined(my $pid = open(my $out, '-|'))
	or bad $test, 'NORUN', "Open pipe from '$runcmd' failed: $!", $log;
    if ($pid == 0) {
	close($out);
	open(STDIN, '<', "/dev/null")
	    or warn "Redirect stdin to /dev/null failed: $!";
	open(STDERR, '>&', \*STDOUT)
	    or warn "Redirect stderr to stdout failed: $!";
	setsid()
	    or warn "Setsid $$ failed: $!";
	exec($runcmd);
	warn "Exec '$runcmd' failed: $!";
	_exit(126);
    }
    eval {
	local $SIG{ALRM} = sub { die "Test running too long, aborted\n" };
	alarm($timeout);
	my $prev = "";
	while (<$out>) {
	    print $log $_;
	    s/[^\s[:print:]]/_/g;
	    print if $opts{v};
	    push @errors, $prev, if /^FAILED$/;
	    chomp($prev = $_);
	}
	alarm(0);
    };
    kill 'KILL', -$pid;
    if ($@) {
	chomp($@);
	bad $test, 'NOTERM', $@, $log;
    }
    close($out)
	or bad $test, 'NOEXIT', $! ?
	"Close pipe from '$runcmd' failed: $!" :
	"Command '$runcmd' failed: $?", $log;
    alarm(0);
    $SIG{ALRM} = 'DEFAULT';

    bad $test, 'FAIL', join(", ", @errors), $log if @errors;
    good $test, $log;
}

close($tr)
    or die "Close 'test.result' after writing failed: $!";

# parse shell script that is setting environment for some tests
# FOO=bar
# FOO="bar"
# export FOO=bar
# export FOO BAR
sub environment {
    my $file = shift;

    open(my $fh, '<', $file)
	or die "Open '$file' for reading failed: $!";
    while (<$fh>) {
	chomp;
	s/\s+$//;
	s/^export\s+(?=\w+=)//;
	s/^export\s+\w+.*//;
	next if /^$/;
	if (/^(\w+)=(\S+)$/ or /^(\w+)="([^"]*)"/ or /^(\w+)='([^']*)'/) {
	    $ENV{$1}=$2;
	} else {
	    die "Unknown environment line in '$file': $_";
	}
    }
}
