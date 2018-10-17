#!/usr/bin/perl
# collect cvs logs between certain dates for sub branches

# Copyright (c) 2018 Alexander Bluhm <bluhm@genua.de>
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
use File::Path qw(make_path);
use Getopt::Std;
use POSIX;
use Time::Local;

use lib dirname($0);
my $scriptname = "$0 @ARGV";

my %opts;
getopts('B:E:P:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -B date [-E date] -P cvspath
    -v          verbose
    -B date     begin date, exclusive
    -E date     end date, inclusive
    -P cvspath	module and path with cvs files
EOF
    exit(2);
};
my $verbose = $opts{v};
$opts{B} or die "No -B begin date";
my ($begin, $end);
$begin = str2time($opts{B})
    or die "Invalid -B date '$opts{B}'";
$end = str2time($opts{E} || $opts{B})
    or die "Invalid -E date '$opts{E}'";
$begin <= $end
    or die "Begin date '$opts{B}' before end date '$opts{E}'";
$opts{P} or die "No -P cvs path";
my ($module, $path) = split("/", $opts{P}, 2);
$module && $path
    or die "Path '$opts{P}' must consist of cvs module / path";

# better get an errno than random kill by SIGPIPE
$SIG{PIPE} = 'IGNORE';

my $performdir = dirname($0). "/..";
chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
$performdir = getcwd();

# collect cvs log data

-f "/usr/$module/CVS/Root"
    or die "No cvs root at /usr/$module, do a checkout";
chdir("/usr/$module")
    or die "Chdir to '/usr/$module' failed: $!";

my $cvsbegin = strftime("%FZ%T", gmtime($begin));
my $cvsend = strftime("%FZ%T", gmtime($end));
my $cvsdate = "-d$cvsbegin<=$cvsend";

my @cvscmd = (qw(cvs -qR rlog -b -N), $cvsdate, "$module/$path");
print "Pipe from command '@cvscmd' started\n" if $verbose;
open(my $cvs, '-|', @cvscmd)
    or die "Open pipe from '@cvscmd' failed: $!";

my $startcommit = "-" x 28;
my $finishcommit = "=" x 77;

my %l;
my $state = "header";
my $file;
my %commit;
while (<$cvs>) {
    print if $verbose;
    chomp;
    if ($_ eq $startcommit || $_ eq $finishcommit) {
	$file or die "No file before commit: $_";
	if ($state eq "header") {
	    my @keys = keys %commit;
	    @keys
		and die "Unexpected keys '@keys' in log: $_";
	} elsif ($state eq "message") {
	    my ($current, $date, $commitid, $author) =
		@commit{qw(current date commitid author)};
	    # maybe a bug in cvs; dead commits outside of -d appear in log
	    if ($begin < $current && $current <= $end) {
		my $lc = $l{$date}{$commitid} ||= {};
		if ($lc->{author}) {
		    $lc->{author} eq $author
			or die "Mismatch date '$date', commitid $commitid, ".
			"autor '$author': $_";
		} else {
		    $lc->{author} = $author,
		    $lc->{message} = $commit{message},
		}
		push @{$lc->{files}}, $file;
	    }
	    undef %commit;
	} else {
	    die "Unexpected state '$state' at commit: $_";
	}
	$state = "commit";
	if ($_ eq $finishcommit) {
	    $state = "header";
	    undef $file;
	}
    } elsif ($state eq "header") {
	if (/^RCS file: (\S+)/) {
	    $file and die "Reset file '$file' in header: $_";
	    $file = $1;
	    $file =~ s,.*?/(?=$module/$path/),,
		or die "No cvs path '/$module/$path/' in rcs file: $_";
	    $file =~ s/,v$//
		or die "No suffix ',v' in rcs file: $_";
	}
    } elsif ($state eq "commit") {
	if (/^revision (\S+)/) {
	    $commit{revision} and die
		"Reset revision '$commit{revision}' in file '$file': $_";
	    my $revision = $1;
	    $revision =~ /^1(\.\d+)+$/
		or die "Unexpected revision '$revision' in file '$file': $_";
	    $commit{revision} = $revision;
	} elsif (/^date: /) {
	    $commit{revision} or die "No revision in file '$file': $_";
	    foreach my $pair (split(";")) {
		$pair =~ /(\w+): (.*)/
		    or die "No key value pair '$pair' in '$file': $_";
		$commit{$1} = $2;
	    }
	    my $current = str2time($commit{date}, "UTC")
		or die "Could not parse date '$commit{date}': $_";
	    $commit{current} = $current;
	    $commit{date} = strftime("%FT%TZ", gmtime($current));
	    $commit{message}
		and die "Reset message '$commit{message}' in file '$file': $_";
	    $commit{message} = [];
	    $state = "message";
	} else {
	    die "Unknown commit: $_";
	}
    } elsif ($state eq "message") {
	push @{$commit{message}}, $_;
    } else {
	die "Unknown state '$state': $_";
    }
}

close($cvs) or die $! ?
    "Close pipe from '@cvscmd' failed: $!" :
    "Command '@cvscmd' failed: $?";
print "Pipe from command '@cvscmd' finished\n" if $verbose;

use Data::Dumper;
print Dumper(\%l);
exit 0;

# write result log file

chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
my $cvslogdir = "results/cvslog/$module/$path";
-d $cvslogdir || make_path $cvslogdir
    or die "Make cvslog path '$cvslogdir' failed: $!";

my $isobegin = strftime("%FT%TZ", gmtime($begin));
my $isoend = strftime("%FT%TZ", gmtime($end));
my $logfile = "$cvslogdir/$isobegin--$isoend.log";
