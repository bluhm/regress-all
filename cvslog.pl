#!/usr/bin/perl
# collect cvs logs between certain dates for sub branches

# Copyright (c) 2018-2020 Alexander Bluhm <bluhm@genua.de>
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
use HTML::Entities;
use POSIX;
use Time::Local;
use URI::Escape;

my $now = strftime("%FT%TZ", gmtime);

use lib dirname($0);
my $scriptname = "$0 @ARGV";

my %opts;
getopts('B:E:P:v', \%opts) or do {
    print STDERR <<"EOF";
usage: $0 [-v] -B date [-E date] -P cvspath
    -v		verbose
    -B date	begin date, exclusive
    -E date	end date, inclusive
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
	    my ($current, $date, $commitid, $author, $revision) =
		@commit{qw(current date commitid author revision)};
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
		push @{$lc->{revisions}}, $revision;
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
if ($state eq "header") {
    my @keys = keys %commit;
    @keys
	and die "Unexpected keys '@keys' after log";
} else {
    die "Unexpected state '$state' after log";
}

close($cvs) or die $! ?
    "Close pipe from '@cvscmd' failed: $!" :
    "Command '@cvscmd' failed: $?";
print "Pipe from command '@cvscmd' finished\n" if $verbose;

# write result log file

chdir($performdir)
    or die "Chdir to '$performdir' failed: $!";
my $cvslogdir = "results/cvslog/$module/$path";
-d $cvslogdir || make_path $cvslogdir
    or die "Make cvslog path '$cvslogdir' failed: $!";

my $isobegin = strftime("%FT%TZ", gmtime($begin));
my $isoend = strftime("%FT%TZ", gmtime($end));
my $logfile = "$cvslogdir/$isobegin--$isoend";

open(my $fh, '>', "$logfile.txt.new")
     or die "Open '$logfile.txt.new' for writing failed: $!";
open(my $html, '>', "$logfile.html.new")
    or die "Open '$logfile.html.new' for writing failed: $!";

print $fh "BEGIN $isobegin\n";
print $fh "END $isoend\n";
print $fh "PATH $module/$path\n";
my $commitnum = keys %l;
print $fh "COMMITS $commitnum\n";

print $html <<"HEADER";
<!DOCTYPE html>
<html>

<head>
  <title>OpenBSD CVS Log</title>
  <style>
    table.commit { border: 1px solid black; }
    th { text-align: left; vertical-align: top; white-space: nowrap; }
    tr:hover {background-color: #e0e0e0}
  </style>
</head>

<body>
<h1>OpenBSD cvs log</h1>
<table>
  <tr>
    <th>created</th>
    <td>$now</td>
  </tr>
  <tr>
    <th>begin</th>
    <td>$isobegin</td>
  </tr>
  <tr>
    <th>end</th>
    <td>$isoend</td>
  </tr>
  <tr>
    <th>path</th>
    <td>$module/$path</td>
  </tr>
  <tr>
    <th>commits</th>
    <td>$commitnum</td>
  </tr>
</table>
HEADER

my $cvsweb = "https://cvsweb.openbsd.org";
foreach my $date (sort keys %l) {
    while ((undef, my $commit) = each %{$l{$date}}) {
	print $fh "\n";
	print $fh "DATE $date\n";
	my $author = $commit->{author};
	print $fh "AUTHOR $author\n";
	my @files = @{$commit->{files}};
	my @revisions = @{$commit->{revisions}};
	my $filespan = @files;
	my $files = "";
	foreach my $f (@files) {
	    $files .= "\n  </tr>\n  <tr>\n" if $files;
	    $files .= "    <td>$f</td>\n";
	    my $rev = shift @revisions;
	    my $link = "$cvsweb/$f#rev$rev";
	    $files .= "    <td><a href=\"$link\">log</a></td>\n";
	    (my $prev = $rev) =~ s/(?<=\.)\d+/$&-1/e;
	    $link = "$cvsweb/$f.diff?r1=$prev&r2=$rev";
	    $files .= "    <td><a href=\"$link\">diff</a></td>\n";
	    $link = "$cvsweb/$f?annotate=$rev";
	    $files .= "    <td><a href=\"$link\">annotate</a></td>";
	}
	print $fh "FILES @files\n";
	my @message = @{$commit->{message}};
	my $message = join("<br>\n\t", map { encode_entities($_) } @message);
	print $fh "MESSAGE @message\n";

	print $html <<"TABLE";
<p>
<table class="commit">
  <tr>
    <th>date</th>
    <td colspan="4">$date</td>
  </tr>
  <tr>
    <th>author</th>
    <td colspan="4">$author</td>
  </tr>
  <tr>
    <th rowspan="$filespan">files</th>
$files
  </tr>
  <tr>
    <th>message</th>
    <td colspan="4">
	$message
    </td>
  </tr>
</table>
TABLE
    }
}

print $html <<"FOOTER";
</body>
</html>
FOOTER

close($fh)
    or die "Close '$logfile.txt.new' after writing failed: $!";
rename("$logfile.txt.new", "$logfile.txt")
    or die "Rename '$logfile.txt.new' to '$logfile.txt' failed: $!";
close($html)
    or die "Close '$logfile.html.new' after writing failed: $!";
rename("$logfile.html.new", "$logfile.html")
    or die "Rename '$logfile.html.new' to '$logfile.html' failed: $!";
