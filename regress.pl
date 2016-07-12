#!/usr/bin/perl

use strict;
use warnings;

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

open(my $tr, '>', "test.result")
    or die "Open 'test.result' for writing failed: $!";

sub bad($$$) {
    my ($test, $reason, $message) = @_;

    print $tr join("\t", $test, $reason, $message);
    no warnings 'exiting';
    next;
}

foreach my $test (@tests) {
    my $dir = $test =~ m,^/, ? $test : "/usr/src/regress/$test";
    chdir($dir)
	or bad $test, 'NOEXIST', "Chdir to $dir failed: $!";
    warn "I was Here";
}

close($tr)
    or die "Close 'test.result' after writing failed: $!";
