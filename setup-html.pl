#!/usr/bin/perl
# convert test setup details to a html table

use strict;
use warnings;
use File::Basename;
use Getopt::Std;
use POSIX;

my $now = strftime("%FT%TZ", gmtime);

my %opts;
getopts('d:', \%opts) or do {
    print STDERR "usage: $0 -d date\n";
    exit(2);
};
my $date = $opts{d} or die "No -d specified";

my $dir = dirname($0). "/../results";
chdir($dir)
    or die "Chdir to '$dir' failed: $!";
chdir($date)
    or die "Chdir to '$date' failed: $!";

my @setups = sort glob("setup-*.log");

my %h;
foreach my $setup (glob("setup-*.log")) {
    my ($host) = $setup =~ m,setup-(.*)\.log,;
    $h{$host} = {
	setup => $setup,
    };
}
foreach my $version (glob("version-*.txt")) {
    my ($host) = $version =~ m,version-(.*)\.txt,;
    open(my $fh, '<', $version)
	or die "Open '$version' for reading failed: $!";
    my ($time) = <$fh> =~ m,: (\w+ \w+ \d+ \d+:\d+:\d+.*)$,;
    $h{$host} = {
	version => $version,
	time => $time,
    };
}

open(my $html, '>', "setup.html")
    or die "Open 'setup.html' for writing failed: $!";
print $html "<!DOCTYPE html>\n";
print $html "<html>\n";
print $html "<head>\n";
print $html "  <title>OpenBSD Test Setup</title>\n";
print $html "</head>\n";

print $html "<body>\n";
print $html "<h1>OpenBSD regress test machine setup at $now</h1>\n";
print $html "<table>\n";
print $html "  <tr>\n    <th>machine</th>\n";
print $html "    <th>version</th>\n";
print $html "    <th>setup</th>\n";
print $html "  </tr>\n";

foreach my $host (sort keys %h) {
    print $html "  <tr>\n    <th>$host</th>\n";
    my $time = $h{$host}{time} || "";
    my $version = $h{$host}{version} || "";
    my $setup = $h{$host}{setup} || "";
    print $html "    <td><a href=\"$version\">$time</a></td>\n";
    print $html "    <td><a href=\"$setup\">log</a></td>\n";
    print $html "  </tr>\n";
}
print $html "</table>\n";
print $html "</body>\n";

print $html "</html>\n";
close($html)
    or die "Close 'setup.html' after writing failed: $!";
